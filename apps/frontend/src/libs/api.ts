import axios from 'axios'

const BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000/api/v1'
const TASK_STATUS_TIMEOUT_MS = Number(import.meta.env.VITE_TASK_STATUS_TIMEOUT_MS || 1800000) // 30 minutes

// 创建 axios 实例
const api = axios.create({
	baseURL: BASE_URL,
	timeout: 60000 // 60秒超时
})

// 请求拦截器
api.interceptors.request.use(
	config => {
		// 可以在这里添加 token 等认证信息
		return config
	},
	error => {
		return Promise.reject(error)
	}
)

// 响应拦截器
api.interceptors.response.use(
	response => {
		return response
	},
	error => {
		if (error?.code === 'ERR_CANCELED') {
			return Promise.reject(error)
		}
		// 统一错误处理
		if (error.response) {
			// 服务器返回了错误状态码
			console.error('API Error:', error.response.data)
		} else if (error.request) {
			// 请求已发出但没有收到响应
			console.error('Network Error:', error.request)
		} else {
			// 其他错误
			console.error('Error:', error.message)
		}
		return Promise.reject(error)
	}
)

// API 统一响应格式
export interface ApiResponse<T> {
	success: boolean
	data: T
	message?: string | null
	error?: string | null
}

// 上传接口返回的 data 结构
export interface UploadTaskData {
	task_id: string | number
	document_id: string
	created_at: string
	priority: string | number
	status: string
	error?: string | null
	message?: string | null
}

export interface UploadTaskResponse extends ApiResponse<UploadTaskData> {}

export interface UploadTaskParams {
	file: File
	custom_url?: string
	batch_size?: number
}

export type TaskStatus = 'pending' | 'processing' | 'completed' | 'failed'

// 轮询接口返回的 data 结构
export interface TaskStatusData {
	task_id: string | number
	document_id: string
	status: TaskStatus
	progress?: number
	processed_pages?: number
	total_pages?: number
	batch_size?: number
	batch_index?: number
	preview_truncated?: boolean
	preview_skipped_blocks?: number
	current_stage?: string | null
	created_at: string
	started_at?: string
	completed_at?: string
	error_message?: string | null
	result_file_path?: string
	result?: {
		output_path?: string
		output_files?: string[]
		metadata?: {
			total_pages?: number
			total_text_length?: number
			word_count?: number
			processing_mode?: string
			source_type?: string
		}
		execution_time?: number
		stage_results?: any
	}
	priority: number
	full_markdown?: string
	metadata?: {
		task_id?: string
		document_id?: string
		original_filename?: string
		processing_mode?: string
		total_pages?: number
		merge_timestamp?: number
		width?: number
		height?: number
	}
	layout?: Array<{
		block_content: string
		bbox: [number, number, number, number]
		block_id: number
		layout_type?: string
		text_length?: number | null
		page_index: number
	}>
	images?: Record<string, string>
	package_download_url?: string
	package_zip_path?: string
	package_dir?: string
}

export interface TaskStatusResponse extends ApiResponse<TaskStatusData> {}

export interface GetTaskStatusParams {
	previewBlocks?: number
	signal?: AbortSignal
}

export interface ManualOverrideItem {
	page_index: number
	block_id?: number
	bbox?: [number, number, number, number]
	layout_type: 'text' | 'image' | 'table'
	content?: string
}

/**
 * 上传文件并创建 OCR 任务
 * @param params 上传参数
 * @returns Promise<UploadTaskData>
 */
export async function uploadTask(params: UploadTaskParams): Promise<UploadTaskData> {
	const formData = new FormData()
	formData.append('file', params.file)
	formData.append('processing_mode', 'pipeline')
	formData.append('batch_size', String(params.batch_size ?? 50))
	if (params.custom_url) {
		formData.append('custom_url', params.custom_url)
	}

	const response = await api.post<UploadTaskResponse>('/tasks/upload', formData)

	if (!response.data.success) {
		throw new Error(response.data.message || 'Upload failed')
	}

	return response.data.data
}

/**
 * 查询任务状态
 * @param taskId 任务 ID
 * @returns Promise<TaskStatusData>
 */
export async function getTaskStatus(
	taskId: string | number,
	params?: GetTaskStatusParams
): Promise<TaskStatusData> {
	const response = await api.get<TaskStatusResponse>(`/tasks/${taskId}`, {
		params: {
			preview_blocks: params?.previewBlocks
		},
		signal: params?.signal,
		timeout: TASK_STATUS_TIMEOUT_MS
	})

	if (!response.data.success) {
		throw new Error(response.data.message || 'Failed to query task status')
	}

	return response.data.data
}

export async function saveTaskOverrides(
	taskId: string | number,
	overrides: ManualOverrideItem[],
	replace: boolean = false
): Promise<void> {
	await api.post(`/tasks/${taskId}/overrides`, {
		overrides,
		replace
	})
}

export default api
