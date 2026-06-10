import { useEffect, useMemo } from 'react'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import type { TaskResponse } from './FileUpload'
import { MarkdownPreview } from '@/components/ocr/MarkdownPreview'
import { useOcrStore } from '../../store/useOcrStore'
import { AppWindowIcon, CopyIcon, DownloadIcon, FileJsonIcon } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { toast } from 'sonner'
import { JsonPreview } from '@/components/ocr/JsonPreview'
// import { data as mockData } from './data'

interface OCRResultsProps {
	result: TaskResponse | null
	fileName?: string
}

export function OCRResults({ result, fileName }: OCRResultsProps) {
	const setBlocks = useOcrStore(s => s.setBlocks)
	const clickedPdfBlockId = useOcrStore(s => s.clickedPdfBlockId)
	const manualTypes = useOcrStore(s => s.manualTypes)
	const setManualBlockType = useOcrStore(s => s.setManualBlockType)
	const progress = result?.response?.progress ?? 0
	const processedPages = result?.response?.processed_pages ?? 0
	const totalPages = result?.response?.total_pages ?? 0

	// 从真实数据中获取 layout 和 images，如果没有则使用 mock 数据
	const layout = useMemo(() => result?.response?.layout || [], [result?.response?.layout])
	const images = useMemo(() => result?.response?.images || {}, [result?.response?.images])


	// 获取 PDF 单页高度	
	const pageHeight = result?.response?.metadata?.height ?? 2339

	// 将 layout 转换为 blocks 格式（过滤掉只有 # 的内容，保留图片）
	const blocks = useMemo(() => {
		if (!(result?.status === 'completed' || result?.status === 'processing' || result?.status === 'pending')) {
			return []
		}
		return layout
			.filter((b: any) => {
				// 过滤掉空内容或只有 # 的内容
				if (!b.block_content || b.block_content.trim() === '') {
					return false
				}
				return true
			})
			.map((b: any, index: number) => {
				const blockContent = b.block_content.trim()
				const blockId = b.block_id ?? index + Math.random() * 1000000
				const rawType = (b.layout_type || '').toLowerCase()
				const manualType = manualTypes[blockId as number]
				const effectiveType = manualType || (rawType.includes('image') ? 'image' : rawType.includes('table') ? 'table' : 'text')

				// 处理 bbox 坐标 - 始终使用相对坐标（每页内的坐标）
				let bbox: [number, number, number, number] | null = null
				let width = 0
				let height = 0
				if (b.bbox) {
					const [x1, y1, x2, y2] = b.bbox as [number, number, number, number]
					width = x2 - x1
					height = y2 - y1

					// 始终使用相对坐标（每页内的坐标）
					bbox = [x1, y1, x2, y2]
				}

				return {
					id: blockId,
					content: blockContent,
					bbox,
					pageIndex: b.page_index ?? 1,
					layoutType: effectiveType,
					manualType,
					isImage: effectiveType === 'image' || blockContent.includes('<img '),
					width: width,
					height: height
				}
			})
	}, [layout, images, pageHeight, result?.status, manualTypes])

	// 将 blocks 设置到 store
	useEffect(() => {
		if (blocks.length > 0) {
			setBlocks(blocks)
		}
	}, [blocks, setBlocks])

	const handleCopy = () => {
		if (!result?.response?.full_markdown) return
		navigator.clipboard.writeText(result.response.full_markdown)
		toast.success('Copied successfully')
	}

	const handleDownload = () => {
		if (!result?.response?.full_markdown) return
		const blob = new Blob([result.response.full_markdown], { type: 'text/markdown' })
		const url = URL.createObjectURL(blob)
		const a = document.createElement('a')
		a.href = url
		a.download = `${fileName || 'result'}.md`
		a.click()
		URL.revokeObjectURL(url)
		toast.success('Downloaded successfully')
	}

	const handleDownloadPackage = () => {
		const packageUrl = (result?.response as any)?.package_download_url as string | undefined
		if (!packageUrl) return
		window.open(packageUrl, '_blank')
	}

	const response = result?.response
	const status = result?.status
	const error_message = result?.error_message
	const selectedLayoutBlock = useMemo(() => {
		if (!clickedPdfBlockId) return null
		return layout.find((b: any) => Number(b.block_id) === Number(clickedPdfBlockId)) || null
	}, [clickedPdfBlockId, layout])
	const selectedBlockType = selectedLayoutBlock
		? manualTypes[Number(selectedLayoutBlock.block_id)] || ((selectedLayoutBlock.layout_type || '').includes('image') ? 'image' : (selectedLayoutBlock.layout_type || '').includes('table') ? 'table' : 'text')
		: 'text'
	const computedProgress = totalPages > 0
		? Math.min(100, Math.max(progress, (processedPages / totalPages) * 100))
		: progress

	return (
		<div className='h-screen flex flex-col bg-white border-l border-border'>
			<Tabs defaultValue='markdown' className='flex-1 flex flex-col overflow-hidden'>
				{(status === 'pending' || status === 'processing') && (
					<div className='px-4 pt-3 pb-2 bg-white border-b border-border'>
						<div className='flex items-center justify-between text-xs text-gray-600 mb-2'>
							<span>
								Processing {totalPages > 0 ? `${processedPages}/${totalPages} pages` : 'document'}
							</span>
							<span>{Math.round(computedProgress)}%</span>
						</div>
						<div className='h-2 rounded-full bg-gray-200 overflow-hidden'>
							<div
								className='h-full bg-blue-600 transition-all duration-500'
								style={{ width: `${Math.max(2, Math.min(100, computedProgress))}%` }}
							/>
						</div>
						{response?.preview_truncated && (
							<p className='mt-2 text-[11px] text-gray-500'>
								Showing latest content window for performance (skipped blocks: {response?.preview_skipped_blocks || 0}).
							</p>
						)}
					</div>
				)}
				{selectedLayoutBlock && (
					<div className='px-4 pb-2 bg-white border-b border-border flex items-center gap-2'>
						<span className='text-xs text-gray-600'>Selected block type:</span>
						<select
							value={selectedBlockType}
							onChange={e => setManualBlockType(Number(selectedLayoutBlock.block_id), e.target.value as 'text' | 'image' | 'table')}
							className='text-xs border rounded px-2 py-1 bg-white'>
							<option value='text'>Text</option>
							<option value='image'>Image</option>
							<option value='table'>Table</option>
						</select>
						<span className='text-[11px] text-gray-500'>Manual assist for OCR mis-detection (preview-side).</span>
					</div>
				)}
				{/* 固定在顶部的 TabsList */}
				<div className='px-4 pt-4 pb-0 bg-white sticky top-0 z-10 flex items-center justify-between'>
					<TabsList className='grid grid-cols-2'>
						<TabsTrigger value='markdown' className='cursor-pointer'>
							<AppWindowIcon className='size-4' />Markdown</TabsTrigger>
						<TabsTrigger value='json' className='cursor-pointer'>
							<FileJsonIcon className='size-4' />JSON</TabsTrigger>
					</TabsList>
					{status === 'completed' && <div className='flex items-center gap-2'>
						<Button variant="outline" className='cursor-pointer' onClick={() => handleDownloadPackage()} disabled={!(result?.response as any)?.package_download_url}>
							Download Package
						</Button>
						<Button variant="outline" size="icon" className='cursor-pointer' onClick={() => handleCopy()}>
							<CopyIcon className='size-4' />
						</Button>
						<Button variant="outline" size="icon" className='cursor-pointer' onClick={() => handleDownload()}>
							<DownloadIcon className='size-4' />
						</Button>
					</div>}
				</div>

				{/* 可滚动的内容区域 */}
				<div className='flex-1 overflow-hidden'>
					<TabsContent value='markdown' className='h-full m-0 mt-0'>
						{/* 解析中状态 */}
						{(status === 'pending' || status === 'processing') && blocks.length === 0 ? (
							<div className='h-full flex items-center justify-center'>
								<div className='text-center'>
									<div className='inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-primary mb-4'></div>
									<p className='text-gray-500 dark:text-gray-400'>
										Processing...
									</p>
								</div>
							</div>
						) : blocks.length > 0 && (status === 'completed' || status === 'processing' || status === 'pending') ? (
							// progressively render available content while processing
							<MarkdownPreview />
						) : status === 'completed' ? (
							// 解析完成但没有内容
							<div className='h-full flex items-center justify-center'>
								<div className='p-4 rounded-lg text-center text-gray-500 dark:text-gray-400'>
									<p>No Markdown content yet</p>
								</div>
							</div>
						) : status === 'failed' ? (
							// 解析失败
							<div className='h-full flex items-center justify-center'>
								<div className='p-4 rounded-lg text-center text-red-500 dark:text-red-400'>
									<p>Processing failed</p>
									{error_message && (
										<p className='text-sm mt-2 text-gray-500 dark:text-gray-400'>
											{error_message}
										</p>
									)}
								</div>
							</div>
						) : (
							// 未上传文件
							<div className='h-full flex items-center justify-center'>
								<div className='p-4 rounded-lg text-center text-gray-500 dark:text-gray-400'>
									<p>Please upload a file and wait for processing</p>
								</div>
							</div>
						)}
					</TabsContent>

					<TabsContent value='json' className='h-full m-0 mt-0 overflow-auto'>
						<div className='p-4'>
							{response && status === 'completed' && result?.response ? (
								<div className='bg-gray-100 dark:bg-gray-800 p-4 rounded-lg overflow-auto'>
									<JsonPreview json={response} />
								</div>
							) : (
								<div className='h-full flex items-center justify-center'>
									<div className='p-4 rounded-lg text-center text-gray-500 dark:text-gray-400'>
										<p>No data yet</p>
									</div>
								</div>
							)}
						</div>
					</TabsContent>
				</div>
			</Tabs>
		</div>
	)
}
