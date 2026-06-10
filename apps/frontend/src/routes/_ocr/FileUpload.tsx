import { useState, useRef, useEffect } from 'react'
import { Upload, Loader2 } from 'lucide-react'
import { cn } from '@/libs/utils'
import { uploadTask, getTaskStatus, type TaskStatus, type TaskStatusData } from '@/libs/api'
import { toast } from 'sonner'


export type Layout = {
	block_content: string
	bbox: [number, number, number, number] | null
	block_id: number
	text_length?: number | null
}

export interface UploadedFile {
	id: string
	name: string
	size: number
	type: string
	file: File
	uploadTime: Date
	error: string | null
}

export interface TaskResponse {
	fileId: string
	status: TaskStatus
	response: TaskStatusData | null
	error_message?: string | null
}

interface FileUploadProps {
	onFileUploaded: (params: UploadedFile) => void
	onTaskStatusChange?: (params: TaskResponse) => void
}

// 允许的文件格式
const ALLOWED_FILE_TYPES = [
	'image/png',
	'image/jpeg',
	'image/jpg',
	'application/pdf',
	'application/msword',
	'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
]

// 允许的文件扩展名（用于备用验证）
const ALLOWED_EXTENSIONS = ['.png', '.jpg', '.jpeg', '.pdf', '.doc', '.docx']

// 验证文件类型
const isValidFileType = (file: File): boolean => {
	// 检查 MIME 类型
	if (ALLOWED_FILE_TYPES.includes(file.type)) {
		return true
	}

	// 备用检查：通过文件扩展名
	const fileName = file.name.toLowerCase()
	return ALLOWED_EXTENSIONS.some(ext => fileName.endsWith(ext))
}

export function FileUpload({ onFileUploaded, onTaskStatusChange }: FileUploadProps) {
	const PREVIEW_BLOCK_OPTIONS = [1200, 2500, 5000]
	const [selectedFile, setSelectedFile] = useState<UploadedFile | null>(null)
	const [isDragging, setIsDragging] = useState(false)
	const [previewBlocks, setPreviewBlocks] = useState<number>(1200)
	const previewBlocksRef = useRef<number>(1200)
	const fileInputRef = useRef<HTMLInputElement>(null)
	const pollingIntervalsRef = useRef<Map<string, NodeJS.Timeout>>(new Map())
	const pollingErrorCountsRef = useRef<Map<string, number>>(new Map())
	const pollingInFlightRef = useRef<Map<string, boolean>>(new Map())
	const pollingRequestStartedAtRef = useRef<Map<string, number>>(new Map())
	const pollingAbortControllersRef = useRef<Map<string, AbortController>>(new Map())
	const [isLoading, setIsLoading] = useState(false)

	useEffect(() => {
		previewBlocksRef.current = previewBlocks
	}, [previewBlocks])


	const handleDragOver = (e: React.DragEvent) => {
		if (isLoading) return
		e.preventDefault()
		setIsDragging(true)
	}

	const handleDragLeave = (e: React.DragEvent) => {
		if (isLoading) return
		e.preventDefault()
		setIsDragging(false)
	}

	const handleDrop = (e: React.DragEvent) => {
		if (isLoading) return
		e.preventDefault()
		setIsDragging(false)

		const droppedFiles = Array.from(e.dataTransfer.files)
		if (droppedFiles.length > 0) {
			handleFile(droppedFiles[0])
		}
	}

	const handleFileInput = (e: React.ChangeEvent<HTMLInputElement>) => {
		if (isLoading) return
		const selectedFiles = e.target.files
		if (selectedFiles && selectedFiles.length > 0) {
			handleFile(selectedFiles[0])
			// 重置 input 的值，这样下次选择相同文件时也能触发 onChange
			if (fileInputRef.current) {
				fileInputRef.current.value = ''
			}
		}
	}

	const handleFile = async (file: File) => {
		// 验证文件类型
		if (!isValidFileType(file)) {
			toast.error(
				`Unsupported file format. Supported formats: ${ALLOWED_EXTENSIONS.join(', ').toUpperCase()}`
			)
			// 重置 input 的值
			if (fileInputRef.current) {
				fileInputRef.current.value = ''
			}
			return
		}

		setIsLoading(true)
		const uploadedFile: UploadedFile = {
			id: `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
			name: file.name,
			size: file.size,
			type: file.type,
			file: file,
			uploadTime: new Date(),
			error: null
		}
		setSelectedFile(uploadedFile)


		try {
			const uploadParams: Parameters<typeof uploadTask>[0] = {
				file: file,
				custom_url: undefined
			}

			const response = await uploadTask(uploadParams)

			// 上传成功，更新文件状态并开始轮询
			const taskId = String(response.task_id)

			onFileUploaded(uploadedFile)

			// 开始轮询任务状态
			if (taskId) {
				startPolling(uploadedFile.id, taskId)
			}
		} catch (error: any) {
			// 上传失败
			const errorMessage = error.response?.data?.message || error.message || 'File upload failed'
			toast.error(errorMessage)
			setSelectedFile(null)
			setIsLoading(false)
		}
	}

	// 开始轮询任务状态
	const startPolling = (fileId: string, taskId: string | number) => {
		// 如果已经有轮询在进行，先清除
		stopPolling(fileId)
		pollingErrorCountsRef.current.set(fileId, 0)

		// 立即查询一次
		pollTaskStatus(fileId, taskId)

		// 设置定时轮询，避免过于频繁触发超时
		const interval = setInterval(() => {
			pollTaskStatus(fileId, taskId)
		}, 5000)

		pollingIntervalsRef.current.set(fileId, interval)
	}

	// 停止轮询
	const stopPolling = (fileId: string) => {
		const controller = pollingAbortControllersRef.current.get(fileId)
		if (controller) {
			controller.abort()
		}
		const interval = pollingIntervalsRef.current.get(fileId)
		if (interval) {
			clearInterval(interval)
			pollingIntervalsRef.current.delete(fileId)
		}
		pollingErrorCountsRef.current.delete(fileId)
		pollingInFlightRef.current.delete(fileId)
		pollingRequestStartedAtRef.current.delete(fileId)
		pollingAbortControllersRef.current.delete(fileId)
	}

	// 查询任务状态
	const pollTaskStatus = async (fileId: string, taskId: string | number) => {
		const now = Date.now()
		if (pollingInFlightRef.current.get(fileId)) {
			const startedAt = pollingRequestStartedAtRef.current.get(fileId) || 0
			// Recover if a request is stuck too long; otherwise, skip overlapping poll.
			if (startedAt && now - startedAt > 120000) {
				pollingAbortControllersRef.current.get(fileId)?.abort()
				pollingInFlightRef.current.set(fileId, false)
			} else {
				return
			}
		}
		pollingInFlightRef.current.set(fileId, true)
		pollingRequestStartedAtRef.current.set(fileId, now)
		const controller = new AbortController()
		pollingAbortControllersRef.current.set(fileId, controller)

		try {
			const response = await getTaskStatus(taskId, {
				previewBlocks: previewBlocksRef.current,
				signal: controller.signal
			})
			const { status, error_message } = response
			pollingErrorCountsRef.current.set(fileId, 0)

			// 更新任务状态（error_message 对应 error），并保存完整的响应
			onTaskStatusChange?.({
				fileId,
				status,
				response,
				error_message
			})

			// 如果任务完成或失败，停止轮询
			if (status === 'completed' || status === 'failed') {
				stopPolling(fileId)
				setIsLoading(false)
			}
		} catch (error: any) {
			const timeoutLike = error?.code === 'ECONNABORTED' || String(error?.message || '').toLowerCase().includes('timeout')
			const abortLike = error?.code === 'ERR_CANCELED' || String(error?.message || '').toLowerCase().includes('aborted') || String(error?.message || '').toLowerCase().includes('canceled')
			if (abortLike) {
				// Cancellation is expected on stale request recovery or component cleanup.
				return
			}
			const networkLike = !error?.response
			const currentFails = (pollingErrorCountsRef.current.get(fileId) || 0) + 1
			pollingErrorCountsRef.current.set(fileId, currentFails)

			console.error('Failed to query task status:', error)

			// Keep polling on transient timeout/network issues.
			if ((timeoutLike || abortLike || networkLike) && currentFails < 60) {
				return
			}

			// Stop only after repeated failures or non-transient errors.
			stopPolling(fileId)
			setIsLoading(false)
			toast.error('Task status polling failed. Please refresh and try again.')
		} finally {
			pollingInFlightRef.current.set(fileId, false)
			pollingRequestStartedAtRef.current.delete(fileId)
			pollingAbortControllersRef.current.delete(fileId)
		}
	}

	// 组件卸载时清理所有轮询
	useEffect(() => {
		return () => {
			pollingIntervalsRef.current.forEach(interval => clearInterval(interval))
			pollingIntervalsRef.current.clear()
		}
	}, [])

	return (
		<div className='h-full flex flex-col bg-white dark:bg-gray-900 border-r border-border'>
			{/* 文件上传区域 */}
			<div className='p-4'>
				<h2 className='text-lg font-semibold mb-4'>File Upload</h2>
				<div
					className={cn(
						'border-2 border-dashed rounded-lg py-8 px-4 text-center cursor-pointer transition-colors',
						isDragging
							? 'border-primary bg-primary/5'
							: 'border-gray-300 dark:border-gray-700 hover:border-primary/50'
					)}
					onDragOver={handleDragOver}
					onDragLeave={handleDragLeave}
					onDrop={handleDrop}
					onClick={() => fileInputRef.current?.click()}>
					{selectedFile?.file && isLoading ? (
						<>
							<div className='flex items-start justify-center gap-2'>
								<Loader2 className='animate-spin' />
								<p className='text-sm font-medium line-clamp-2 break-all leading-6'>
									{selectedFile.name}
								</p>
							</div>
						</>
					) : (
						<>
							<Upload className='size-12 mx-auto mb-4 text-gray-400' />
							<p className='text-sm font-medium mb-1'>Click or drag file here</p>
							<p className='text-xs text-gray-500'>Format: png/jpg/jpeg, pdf, doc, docx</p>
							<p className='text-xs text-gray-400 mt-1'>No file size limit</p>
						</>
					)}
				</div>

				<input
					ref={fileInputRef}
					type='file'
					className='hidden'
					accept='image/*,.pdf,.doc,.docx'
					disabled={isLoading}
					onChange={handleFileInput}
				/>

				<div className='mt-3'>
					<label className='text-xs text-gray-500 block mb-1'>Live preview window</label>
					<select
						className='w-full border rounded-md px-2 py-1 text-xs bg-white dark:bg-gray-800 dark:border-gray-700'
						value={previewBlocks}
						onChange={e => setPreviewBlocks(Number(e.target.value))}
						disabled={isLoading}>
						{PREVIEW_BLOCK_OPTIONS.map(v => (
							<option key={v} value={v}>
								{v} blocks
							</option>
						))}
					</select>
					<p className='mt-1 text-[11px] text-gray-400'>Higher value shows more pages but may slow updates on very large PDFs.</p>
				</div>
			</div>
		</div>
	)
}
