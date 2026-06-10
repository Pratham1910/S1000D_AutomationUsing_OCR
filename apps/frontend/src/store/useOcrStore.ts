import { create } from 'zustand'

export interface Block {
	id: number
	content: string
	bbox: [number, number, number, number] | null
	pageIndex: number
	layoutType?: string
	manualType?: 'text' | 'image' | 'table'
	isImage?: boolean
	width: number
	height: number
}

interface OcrStore {
	hoveredBlockId: number | null  // 悬停的 block id
	clickedBlockId: number | null  // 点击的 block id
	clickedPdfBlockId: number | null
	blocks: Block[]
	customBlocks: Block[]
	manualTypes: Record<number, 'text' | 'image' | 'table'>
	setHoveredBlockId: (blockId: number | null) => void
	setClickedBlockId: (blockId: number | null) => void
	setClickedPdfBlockId: (blockId: number | null) => void
	setBlocks: (blocks: Block[]) => void
	setManualBlockType: (blockId: number, blockType: 'text' | 'image' | 'table', contentOverride?: string) => void
	addCustomBlock: (block: Block) => void
	clearCustomBlocks: () => void
}

export const useOcrStore = create<OcrStore>(set => ({
	hoveredBlockId: null,
	clickedBlockId: null,
	clickedPdfBlockId: null,
	blocks: [],
	customBlocks: [],
	manualTypes: {},
	setHoveredBlockId: blockId =>
		set({ hoveredBlockId: blockId, clickedBlockId: null, clickedPdfBlockId: null }),
	setClickedBlockId: blockId => set({ clickedBlockId: blockId, hoveredBlockId: blockId }),
	setClickedPdfBlockId: blockId => set({ clickedPdfBlockId: blockId, hoveredBlockId: blockId }),
	setBlocks: blocks => set(state => ({
		blocks: [
			...blocks.map(b => ({
			...b,
			manualType: state.manualTypes[b.id]
			})),
			...state.customBlocks,
		],
	})),
	setManualBlockType: (blockId, blockType, contentOverride) =>
		set(state => ({
			manualTypes: { ...state.manualTypes, [blockId]: blockType },
			blocks: state.blocks.map(b =>
				b.id === blockId
					? {
						...b,
						manualType: blockType,
						layoutType: blockType,
						isImage: blockType === 'image',
						content: typeof contentOverride === 'string' ? contentOverride : b.content,
					}
					: b
			)
		})),
	addCustomBlock: (block) =>
		set(state => {
			const nextCustomBlocks = [...state.customBlocks, block]
			return {
				customBlocks: nextCustomBlocks,
				blocks: [...state.blocks, block],
			}
		}),
	clearCustomBlocks: () => set(state => ({
		customBlocks: [],
		blocks: state.blocks.filter(b => !state.customBlocks.some(c => c.id === b.id))
	}))
}))
