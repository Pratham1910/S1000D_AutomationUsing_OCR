import { useState, useEffect, useRef, useMemo, type RefObject } from 'react'
import type { TaskResponse, UploadedFile } from './FileUpload'
import { useOcrStore } from '../../store/useOcrStore'
import PdfViewer from '@/components/ocr/PdfViewer'
import { usePdfPageMetrics } from '@/hooks/usePdfPageMetrics'
import { useFileBlockInteraction } from '@/hooks/useFileBlockInteraction'
import { usePdfScrollToBlock } from '@/hooks/usePdfScrollToBlock'
import { HighlightOverlay } from '@/components/ocr/HighlightOverlay'
import { saveTaskOverrides } from '@/libs/api'
import { toast } from 'sonner'

interface FilePreviewProps {
	file: UploadedFile | null
	result: TaskResponse | null
}

export function FilePreview({ file, result }: FilePreviewProps) {
	const [pdfUrl, setPdfUrl] = useState<string | null>(file?.file?.name || null)
	const viewerRef = useRef<HTMLDivElement>(null)
	const imageRef = useRef<HTMLImageElement>(null)
	const hoveredBlockId = useOcrStore(s => s.hoveredBlockId)
	const clickedBlockId = useOcrStore(s => s.clickedBlockId)
	const clickedPdfBlockId = useOcrStore(s => s.clickedPdfBlockId)
	const setHoveredBlockId = useOcrStore(s => s.setHoveredBlockId)
	const setClickedPdfBlockId = useOcrStore(s => s.setClickedPdfBlockId)
	const setManualBlockType = useOcrStore(s => s.setManualBlockType)
	const addCustomBlock = useOcrStore(s => s.addCustomBlock)
	const manualTypes = useOcrStore(s => s.manualTypes)
	const blocks = useOcrStore(s => s.blocks)

	const [showCopyButton, setShowCopyButton] = useState(false)
	const [drawMode, setDrawMode] = useState(false)
	const [drawType, setDrawType] = useState<'text' | 'image' | 'table'>('text')
	const [draftRect, setDraftRect] = useState<{
		pageIndex: number
		startX: number
		startY: number
		endX: number
		endY: number
	} | null>(null)

	// 获取 PDF 原始尺寸（从 metadata 或默认值）
	const pdfOriginalWidth = result?.response?.metadata?.width ?? 1654
	const pdfOriginalHeight = result?.response?.metadata?.height ?? 2339


	const isValid = useMemo(() => {
		return !isNaN(pdfOriginalWidth) && !isNaN(pdfOriginalHeight) && result?.status === 'completed'
	}, [pdfOriginalWidth, pdfOriginalHeight, result?.status])

	// 获取当前高亮的 block
	const hoveredBlock = hoveredBlockId ? blocks.find(b => b.id === hoveredBlockId) : null
	const clickedBlock = clickedBlockId ? blocks.find(b => b.id === clickedBlockId) : null
	// 优先显示点击的 block，否则显示悬停的 block
	const activeBlock = clickedBlock || hoveredBlock || null
	const selectedPdfBlock = useMemo(() => {
		if (!clickedPdfBlockId) return null
		return blocks.find(b => b.id === clickedPdfBlockId) || null
	}, [clickedPdfBlockId, blocks])
	const selectedBlockType = useMemo(() => {
		if (!selectedPdfBlock) return 'text'
		if (selectedPdfBlock.id && manualTypes[selectedPdfBlock.id]) {
			return manualTypes[selectedPdfBlock.id]
		}
		const layoutType = String(selectedPdfBlock.layoutType || '').toLowerCase()
		if (layoutType.includes('image')) return 'image'
		if (layoutType.includes('table')) return 'table'
		return 'text'
	}, [selectedPdfBlock, manualTypes])

	// 计算图片的缩放比例和偏移量
	const [imageScale, setImageScale] = useState({ x: 1, y: 1, offsetX: 0, offsetY: 0 })
	useEffect(() => {
		if (!imageRef.current || file?.type === 'application/pdf') return

		const updateImageScale = () => {
			const img = imageRef.current
			if (!img) return

			const imgRect = img.getBoundingClientRect()
			const containerRect = img.parentElement?.getBoundingClientRect()
			if (!containerRect) return

			// 计算缩放比例（显示尺寸 / 原始尺寸）
			const scaleX = imgRect.width / img.naturalWidth
			const scaleY = imgRect.height / img.naturalHeight

			// 计算图片在容器中的偏移量（考虑 object-contain 的居中效果）
			const offsetX = imgRect.left - containerRect.left
			const offsetY = imgRect.top - containerRect.top

			setImageScale({ x: scaleX, y: scaleY, offsetX, offsetY })
		}

		// 图片加载完成后更新
		const img = imageRef.current
		if (img.complete) {
			updateImageScale()
		} else {
			img.addEventListener('load', updateImageScale)
		}

		// 监听窗口大小变化
		window.addEventListener('resize', updateImageScale)

		return () => {
			img.removeEventListener('load', updateImageScale)
			window.removeEventListener('resize', updateImageScale)
		}
	}, [pdfUrl, file?.type])

	const pdfPageMetrics = usePdfPageMetrics(
		viewerRef as RefObject<HTMLDivElement>,
		pdfUrl,
		file?.type,
		isValid,
		activeBlock,
		pdfOriginalWidth,
		pdfOriginalHeight
	)

	// 使用 block 交互 hook
	const {
		handlePdfClick,
		handlePdfMouseMove,
		handlePdfMouseLeave,
		handleImageClick,
		handleImageMouseMove,
		handleImageMouseLeave
	} = useFileBlockInteraction({
		blocks,
		resultStatus: result?.status,
		setHoveredBlockId,
		setClickedBlockId: setClickedPdfBlockId,
		setShowCopyButton
	})

	// 使用滚动 hook
	usePdfScrollToBlock(
		clickedBlockId,
		clickedBlock ?? null,
		viewerRef as RefObject<HTMLDivElement>,
		pdfOriginalWidth,
		pdfOriginalHeight,
		result?.status
	)

	useEffect(() => {
		if (!hoveredBlockId && !clickedBlockId) {
			setShowCopyButton(false)
		}
	}, [hoveredBlockId, clickedBlockId])

	// 当文件变化时，创建 URL
	useEffect(() => {
		if (file && (file.type === 'application/pdf' || file.type.startsWith('image/'))) {
			const url = URL.createObjectURL(file.file)
			setPdfUrl(url)

			return () => {
				URL.revokeObjectURL(url)
			}
		} else {
			setPdfUrl(null)
		}
		setDraftRect(null)
	}, [file])

	const createCustomBlock = (bbox: [number, number, number, number], pageIndex: number) => {
		const width = Math.max(1, bbox[2] - bbox[0])
		const height = Math.max(1, bbox[3] - bbox[1])
		if (width < 6 || height < 6) return

		const id = Date.now() + Math.floor(Math.random() * 1000)
		const placeholder = drawType === 'table'
			? '|===\n| Header 1 | Header 2\n| Cell 1 | Cell 2\n|===\n'
			: drawType === 'image'
				? '[Manual image region]'
				: '[Manual text region]'

		addCustomBlock({
			id,
			content: placeholder,
			bbox,
			pageIndex,
			layoutType: drawType,
			manualType: drawType,
			isImage: drawType === 'image',
			width,
			height,
		})
		setClickedPdfBlockId(id)
		const taskId = result?.response?.task_id
		if (taskId) {
			saveTaskOverrides(taskId, [
				{
					page_index: pageIndex,
					bbox,
					layout_type: drawType,
					content: placeholder,
				},
			]).catch(() => {
				toast.error('Failed to save manual region override')
			})
		}
	}

	const getContentForType = (source: string, blockType: 'text' | 'image' | 'table') => {
		const text = (source || '').trim()
		if (blockType === 'image') {
			return '[Manual image region]'
		}
		if (blockType === 'table') {
			if (text.includes('|===')) return text
			const lines = text.split(/\r?\n/).map(l => l.trim()).filter(Boolean)
			if (lines.length >= 2) {
				const rows = lines.map(l => `| ${l.replace(/\s{2,}/g, ' | ')}`)
				return `|===\n${rows.join('\n')}\n|===\n`
			}
			return '|===\n| Header 1 | Header 2\n| Cell 1 | Cell 2\n|===\n'
		}
		return text || '[Manual text region]'
	}

	const applyTypeToSelectedBlock = (blockType: 'text' | 'image' | 'table') => {
		if (!selectedPdfBlock) return
		const overrideContent = getContentForType(selectedPdfBlock.content, blockType)
		setManualBlockType(selectedPdfBlock.id, blockType, overrideContent)
		const taskId = result?.response?.task_id
		if (!taskId) return
		saveTaskOverrides(taskId, [
			{
				page_index: selectedPdfBlock.pageIndex,
				block_id: selectedPdfBlock.id,
				bbox: selectedPdfBlock.bbox || undefined,
				layout_type: blockType,
				content: overrideContent,
			}
		]).catch(() => {
			toast.error('Failed to save block type override')
		})
	}

	const startImageDraw = (e: React.MouseEvent<HTMLDivElement>) => {
		if (!drawMode) return
		const img = imageRef.current
		if (!img) return
		const imgRect = img.getBoundingClientRect()
		const x = (e.clientX - imgRect.left) / Math.max(imageScale.x, 0.0001)
		const y = (e.clientY - imgRect.top) / Math.max(imageScale.y, 0.0001)
		setDraftRect({ pageIndex: 1, startX: x, startY: y, endX: x, endY: y })
	}

	const moveImageDraw = (e: React.MouseEvent<HTMLDivElement>) => {
		if (!drawMode || !draftRect || !imageRef.current) return
		const imgRect = imageRef.current.getBoundingClientRect()
		const x = (e.clientX - imgRect.left) / Math.max(imageScale.x, 0.0001)
		const y = (e.clientY - imgRect.top) / Math.max(imageScale.y, 0.0001)
		setDraftRect(prev => (prev ? { ...prev, endX: x, endY: y } : prev))
	}

	const endImageDraw = () => {
		if (!drawMode || !draftRect) return
		const x1 = Math.min(draftRect.startX, draftRect.endX)
		const y1 = Math.min(draftRect.startY, draftRect.endY)
		const x2 = Math.max(draftRect.startX, draftRect.endX)
		const y2 = Math.max(draftRect.startY, draftRect.endY)
		createCustomBlock([x1, y1, x2, y2], 1)
		setDraftRect(null)
	}

	const getPdfPoint = (e: React.MouseEvent<HTMLDivElement>, pageNumber: number) => {
		const pageWrapper = viewerRef.current?.querySelector(
			`[data-pdf-page="${pageNumber}"]`
		) as HTMLElement | null
		const canvas = pageWrapper?.querySelector('.react-pdf__Page__canvas') as HTMLCanvasElement | null
		if (!pageWrapper || !canvas) return null
		const canvasRect = canvas.getBoundingClientRect()
		const x = (e.clientX - canvasRect.left) * (pdfOriginalWidth / Math.max(canvasRect.width, 1))
		const y = (e.clientY - canvasRect.top) * (pdfOriginalHeight / Math.max(canvasRect.height, 1))
		return { x, y }
	}

	const startPdfDraw = (e: React.MouseEvent<HTMLDivElement>, pageNumber: number) => {
		if (!drawMode) return
		const p = getPdfPoint(e, pageNumber)
		if (!p) return
		setDraftRect({ pageIndex: pageNumber, startX: p.x, startY: p.y, endX: p.x, endY: p.y })
	}

	const movePdfDraw = (e: React.MouseEvent<HTMLDivElement>, pageNumber: number) => {
		if (!drawMode || !draftRect || draftRect.pageIndex !== pageNumber) return
		const p = getPdfPoint(e, pageNumber)
		if (!p) return
		setDraftRect(prev => (prev ? { ...prev, endX: p.x, endY: p.y } : prev))
	}

	const endPdfDraw = () => {
		if (!drawMode || !draftRect) return
		const x1 = Math.min(draftRect.startX, draftRect.endX)
		const y1 = Math.min(draftRect.startY, draftRect.endY)
		const x2 = Math.max(draftRect.startX, draftRect.endX)
		const y2 = Math.max(draftRect.startY, draftRect.endY)
		createCustomBlock([x1, y1, x2, y2], draftRect.pageIndex)
		setDraftRect(null)
	}



	const renderPdfPageOverlay = (pageNumber: number) => {
		const metrics = pdfPageMetrics[pageNumber]
		if (!metrics) return null

		const scaleX = metrics.width / pdfOriginalWidth
		const scaleY = metrics.height / pdfOriginalHeight
		const showActiveBlock = !!activeBlock?.bbox && activeBlock.pageIndex === pageNumber
		const showDraft = !!draftRect && draftRect.pageIndex === pageNumber

		return (
			<>
				{showActiveBlock && activeBlock && (
					<HighlightOverlay
						block={activeBlock}
						showCopyButton={showCopyButton}
						style={{
							left: metrics.offsetX + activeBlock.bbox![0] * scaleX,
							top: metrics.offsetY + activeBlock.bbox![1] * scaleY,
							width: activeBlock.width * scaleX,
							height: activeBlock.height * scaleY
						}}
					/>
				)}
				{showDraft && draftRect && (
					<div
						className='absolute border-2 border-blue-500 border-dashed bg-blue-100/20 pointer-events-none z-20'
						style={{
							left: metrics.offsetX + Math.min(draftRect.startX, draftRect.endX) * scaleX,
							top: metrics.offsetY + Math.min(draftRect.startY, draftRect.endY) * scaleY,
							width: Math.abs(draftRect.endX - draftRect.startX) * scaleX,
							height: Math.abs(draftRect.endY - draftRect.startY) * scaleY,
						}}
					/>
				)}
			</>
		)
	}

	if (!file) {
		return (
			<div className='h-full flex items-center justify-center bg-gray-50 dark:bg-gray-900'>
				<div className='text-center text-gray-500'>
					<p className='text-lg'>Please select or upload a file</p>
				</div>
			</div>
		)
	}

	return (
		<div className='pdf-preview h-screen flex flex-col bg-white dark:bg-gray-900 overflow-hidden relative'>
			<div className='absolute top-3 right-3 z-20 w-72 rounded-lg border border-gray-200 bg-white/95 backdrop-blur px-3 py-3 shadow-md'>
				<p className='text-xs font-semibold text-gray-700'>Manual OCR Assist</p>
				<p className='text-[11px] text-gray-500 mt-1'>Click a detected region or draw a new one.</p>
				<button
					type='button'
					onClick={() => {
						setDrawMode(v => !v)
						setDraftRect(null)
					}}
					className={`mt-2 w-full text-xs rounded-md border px-2 py-1 ${drawMode ? 'bg-orange-500 text-white border-orange-500' : 'bg-white text-gray-700 border-gray-300'}`}>
					{drawMode ? 'Drawing Mode: ON (drag on page)' : 'Enable Draw Region'}
				</button>
				<div className='mt-2'>
					<label className='text-[11px] text-gray-500 block mb-1'>New region type</label>
					<select
						value={drawType}
						onChange={e => setDrawType(e.target.value as 'text' | 'image' | 'table')}
						className='w-full text-xs border rounded px-2 py-1 bg-white'>
						<option value='text'>Text</option>
						<option value='image'>Image</option>
						<option value='table'>Table</option>
					</select>
				</div>
				<div className='mt-3 grid grid-cols-3 gap-2'>
					<button
						type='button'
						disabled={!selectedPdfBlock}
						onClick={() => applyTypeToSelectedBlock('text')}
						className={`text-xs rounded-md border px-2 py-1 ${selectedBlockType === 'text' ? 'bg-blue-600 text-white border-blue-600' : 'bg-white text-gray-700 border-gray-300'} disabled:opacity-50`}>
						Text
					</button>
					<button
						type='button'
						disabled={!selectedPdfBlock}
						onClick={() => applyTypeToSelectedBlock('image')}
						className={`text-xs rounded-md border px-2 py-1 ${selectedBlockType === 'image' ? 'bg-blue-600 text-white border-blue-600' : 'bg-white text-gray-700 border-gray-300'} disabled:opacity-50`}>
						Image
					</button>
					<button
						type='button'
						disabled={!selectedPdfBlock}
						onClick={() => applyTypeToSelectedBlock('table')}
						className={`text-xs rounded-md border px-2 py-1 ${selectedBlockType === 'table' ? 'bg-blue-600 text-white border-blue-600' : 'bg-white text-gray-700 border-gray-300'} disabled:opacity-50`}>
						Table
					</button>
				</div>
				<p className='text-[11px] text-gray-500 mt-2'>
					{selectedPdfBlock
						? `Selected block: #${selectedPdfBlock.id} (page ${selectedPdfBlock.pageIndex})`
						: 'No block selected yet.'}
				</p>
			</div>
			<div className='flex-1 h-full overflow-hidden' ref={viewerRef}>
				{file.type === 'application/pdf' ? (
					<PdfViewer
						file={file.file}
						className='h-full'
						renderPageOverlay={renderPdfPageOverlay}
						onPageClick={(e, pageNumber) => {
							if (!drawMode) handlePdfClick(e, pageNumber, pdfOriginalWidth, pdfOriginalHeight)
						}}
						onPageMouseDown={(e, pageNumber) => {
							if (drawMode) startPdfDraw(e, pageNumber)
						}}
						onPageMouseUp={() => {
							if (drawMode) endPdfDraw()
						}}
						onPageMouseMove={(e, pageNumber) => {
							if (drawMode) {
								movePdfDraw(e, pageNumber)
							} else {
								handlePdfMouseMove(e, pageNumber, pdfOriginalWidth, pdfOriginalHeight)
							}
						}}
						onPageMouseLeave={handlePdfMouseLeave}
					/>
				) : file.type.startsWith('image/') && pdfUrl ? (
					<div
						className={`h-full flex items-center justify-center p-4 overflow-auto relative ${drawMode ? 'cursor-crosshair' : 'cursor-pointer'}`}
						onClick={e => {
							if (!drawMode) handleImageClick(e)
						}}
						onMouseDown={e => {
							if (drawMode) startImageDraw(e)
						}}
						onMouseUp={() => {
							if (drawMode) endImageDraw()
						}}
						onMouseMove={e => {
							if (drawMode) {
								moveImageDraw(e)
							} else {
								handleImageMouseMove(e)
							}
						}}
						onMouseLeave={handleImageMouseLeave}>
						<img
							ref={imageRef}
							src={pdfUrl}
							alt={file.name}
							className='max-w-full max-h-full object-contain'
						/>
						{activeBlock && activeBlock.bbox && (
							<HighlightOverlay
								block={activeBlock}
								showCopyButton={showCopyButton}
								style={{
									left: imageScale.offsetX + activeBlock.bbox[0] * imageScale.x,
									top: imageScale.offsetY + activeBlock.bbox[1] * imageScale.y,
									width: activeBlock.width * imageScale.x,
									height: activeBlock.height * imageScale.y
								}}
								copyButtonClassName='right-6'
							/>
						)}
						{drawMode && draftRect && (
							<div
								className='absolute border-2 border-blue-500 border-dashed bg-blue-100/20 pointer-events-none z-20'
								style={{
									left: imageScale.offsetX + Math.min(draftRect.startX, draftRect.endX) * imageScale.x,
									top: imageScale.offsetY + Math.min(draftRect.startY, draftRect.endY) * imageScale.y,
									width: Math.abs(draftRect.endX - draftRect.startX) * imageScale.x,
									height: Math.abs(draftRect.endY - draftRect.startY) * imageScale.y,
								}}
							/>
						)}
					</div>
				) : (
					<div className='h-full flex items-center justify-center text-gray-500'>
						<p>Unsupported file format</p>
					</div>
				)}
			</div>
		</div>
	)
}
