"""
版面分析和OCR处理步骤
"""

import json
from typing import Dict, Any, Optional, Callable, List, Union
from pathlib import Path
from app.core.ocr_client import LayoutAndOCRClient
import httpx
import base64
import os
from app.core.flows.base import ProcessingContext
from app.utils.config import settings
from app.utils.image_processer import crop_image_by_bbox_to_path, vlm_bbox_convert
from app.utils.logger import logger


class LayoutOcrStepInput:
    image_files_path: List[str]  # 图片文件路径列表
    page_count: Optional[int]  # 页数
    images_dir: Optional[str]  # 图片目录

    def __init__(
        self,
        image_files_path: List[str],
        page_count: Optional[int] = None,
        images_dir: Optional[str] = None,
    ) -> None:
        self.image_files_path = image_files_path
        self.page_count = page_count
        self.images_dir = images_dir


async def layout_and_ocr(
    context: ProcessingContext,
    input: LayoutOcrStepInput,
    progress_callback: Optional[Callable[[float, str], None]] = None,
) -> Dict[str, Any]:
    """
    执行版面分析和OCR处理

    Args:
        context: 处理上下文
        pdf_result: PDF转图片的结果，包含:
            - output_files: list[str] - 图片文件路径列表
            - page_count: int - 页数
            - images_dir: str - 图片目录
        progress_callback: 进度回调函数

    Returns:
        Dict[str, Any]: OCR结果
    """
    task_id = context.task_id
    ocr_config = context.ocr_config

    # 获取图片文件列表
    image_files = input.image_files_path
    images_dir = input.images_dir
    page_count = input.page_count
    page_size = context.metadata.get("page_size")
    logger.info(f"[{task_id}] Starting layout and OCR processing")
    logger.info(f"[{task_id}] Processing {page_count} pages from {images_dir}")

    try:
        # 调用实际的版面分析和OCR服务
        # 这里需要根据实际的OCR API来实现

        # 示例：假设我们有一个OCR客户端
        result = await _call_ocr_service(
            page_size=page_size,
            image_files=image_files,
            images_dir=images_dir,
            page_count=page_count,
            config=ocr_config,
            output_dir=context.get_output_dir(),
            progress_callback=progress_callback,
        )

        logger.info(f"[{task_id}] Layout and OCR processing completed")

        return result

    except Exception as e:
        logger.error(f"[{task_id}] Layout and OCR processing failed: {e}")
        raise


async def _call_ocr_service(
    image_files: list[str],
    images_dir: str,
    page_count: int,
    config: Dict[str, Any],
    output_dir: str,
    page_size: Dict[str, Any],
    progress_callback: Optional[Callable[[float, str], None]] = None,
) -> Dict[str, Any]:
    """
    调用OCR服务

    这里是示例实现，实际需要根据您的OCR服务来调整

    Args:
        image_files: 图片文件路径列表
        images_dir: 图片目录
        page_count: 页数
        config: OCR配置
        output_dir: 输出目录
        progress_callback: 进度回调
    """

    if progress_callback:
        await progress_callback(0.0, f"Initializing OCR service for {page_count} pages")
    custom_url = config.get("custom_url", None)
    cli = LayoutAndOCRClient()
    pages_result = []
    batch_size = max(1, int(config.get("batch_size", 50) or 50))
    snapshot_flush_pages = max(1, int(config.get("snapshot_flush_pages", min(10, batch_size)) or min(10, batch_size)))
    page_width = page_size.get("width")
    page_height = page_size.get("height")
    block_idx = 1
    ref_image_paths = []
    ocr_result_file = Path(output_dir) / "ocr_result.json"

    async def _flush_partial(processed_pages: int, is_partial: bool, batch_index: int):
        snapshot = {
            "success": True,
            "pages": pages_result,
            "total_pages": page_count,
            "processed_pages": processed_pages,
            "images_dir": images_dir,
            "ocr_result_file": f"{ocr_result_file}",
            "ref_image_paths": ref_image_paths,
            "is_partial": is_partial,
            "batch_size": batch_size,
            "batch_index": batch_index,
        }
        try:
            with open(ocr_result_file, "w", encoding="utf-8") as f:
                json.dump(snapshot, f, ensure_ascii=False, indent=2)
            logger.info(
                f"Saved {'partial' if is_partial else 'final'} OCR snapshot: "
                f"{processed_pages}/{page_count} pages"
            )
        except Exception as e:
            logger.error(f"Failed to save OCR snapshot: {e}")
    for i, image_file in enumerate(image_files):
        page_num = i + 1
        result = await cli.process_single_image(image_file, custom_url=custom_url)
        if progress_callback:
            progress = (i / page_count) * 100
            await progress_callback(
                progress, f"Processing page {page_num}/{page_count}"
            )
        page_blocks = []
        for idx, block in enumerate(result):
            block_label = block.get("label", "text")
            block_bbox = block.get("bbox_2d", [0, 0, 0, 0])
            block_content = block.get("content", None)
            block_index = block_idx
            normalized_box = vlm_bbox_convert(block_bbox, page_width, page_height)

            # 如果 label 为 image，则裁剪图片并添加到 image_path 字段
            image_path_field = None
            if block_label == "image":
                try:
                    # 生成分割文件名
                    split_filename = f"split_{page_num}_{block_idx:04d}.png"
                    split_path = os.path.join(output_dir, split_filename)
                    crop_image_by_bbox_to_path(image_file, normalized_box, split_path)
                    image_path_field = split_path
                    ref_image_paths.append(image_path_field)
                    logger.info(f"Cropped image block {block_idx}: {split_filename}")
                except Exception as e:
                    logger.warning(f"Failed to crop image block {block_idx}: {str(e)}")

            # 构建块信息，添加 image_path 字段
            block_info = {
                "layout_type": block_label,
                "layout_box": normalized_box,
                "content": block_content,
                "index": block_index,
                "image_path": image_path_field,  # 图片类型时包含裁剪后的路径
                "page_index": page_num,
            }
            page_blocks.append(block_info)
            block_idx += 1
        # 示例：每页的OCR结果
        pages_result.append(
            {
                "page_index": page_num,
                "image_file": image_file,
                "layout": {"blocks": page_blocks},
            }
        )

        # Flush partial snapshots frequently so progress does not appear stalled on large files.
        if page_num % snapshot_flush_pages == 0 or page_num % batch_size == 0 or page_num == page_count:
            await _flush_partial(
                processed_pages=page_num,
                is_partial=(page_num < page_count),
                batch_index=((page_num - 1) // batch_size) + 1,
            )

    if progress_callback:
        await progress_callback(100.0, "OCR processing completed")

    # Build final return payload from latest snapshot data.
    ocr_result_data = {
        "success": True,
        "pages": pages_result,
        "total_pages": page_count,
        "processed_pages": page_count,
        "images_dir": images_dir,
        "ocr_result_file": f"{ocr_result_file}",
        "ref_image_paths": ref_image_paths,
        "is_partial": False,
        "batch_size": batch_size,
        "batch_index": ((page_count - 1) // batch_size) + 1 if page_count else 0,
    }

    return ocr_result_data

