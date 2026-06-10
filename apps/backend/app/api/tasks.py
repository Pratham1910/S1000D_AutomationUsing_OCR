"""
任务相关API
"""

import json
import os
import uuid
from pathlib import Path
from typing import Optional, List, Any
from datetime import datetime, UTC

from fastapi import APIRouter, HTTPException, status, UploadFile, File, Form, Response, Query
from mimetypes import guess_type

from app.schemas.response import ApiResponse, TaskData, TaskResultData
from app.core.task_manager import get_task_manager
from app.utils.logger import logger
from app.utils.upload_file_manager import file_upload_handler
from app.utils.config import settings


router = APIRouter(prefix="/tasks", tags=["tasks"])


def _manual_overrides_path(task_id: str) -> Path:
    return Path(settings.OUTPUT_DIR) / task_id / "manual_overrides.json"


def _default_content_for_type(layout_type: str) -> str:
    lt = (layout_type or "text").lower()
    if lt == "image":
        return "[Manual image region]"
    if lt == "table":
        return "|===\n| Header 1 | Header 2\n| Cell 1 | Cell 2\n|===\n"
    return "[Manual text region]"


def _load_manual_overrides(task_id: str) -> list[dict]:
    p = _manual_overrides_path(task_id)
    if not p.exists():
        return []
    try:
        return json.loads(p.read_text(encoding="utf-8")) or []
    except Exception:
        return []


def _save_manual_overrides(task_id: str, overrides: list[dict]) -> None:
    p = _manual_overrides_path(task_id)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(overrides, ensure_ascii=False, indent=2), encoding="utf-8")


def _apply_manual_overrides_to_pages(pages: list[dict], overrides: list[dict]) -> list[dict]:
    if not isinstance(pages, list) or not overrides:
        return pages

    for ov in overrides:
        page_index = int(ov.get("page_index") or 1)
        block_id = ov.get("block_id")
        layout_type = (ov.get("layout_type") or "text").lower()
        bbox = ov.get("bbox")
        content = ov.get("content") or _default_content_for_type(layout_type)

        page_obj = next((p for p in pages if int(p.get("page_index") or 0) == page_index), None)
        if page_obj is None:
            page_obj = {"page_index": page_index, "layout": {"blocks": []}}
            pages.append(page_obj)

        blocks = page_obj.setdefault("layout", {}).setdefault("blocks", [])
        target = None
        if block_id is not None:
            target = next((b for b in blocks if int(b.get("index") or -1) == int(block_id)), None)

        if target is not None:
            target["layout_type"] = layout_type
            target["content"] = content
            if isinstance(bbox, list) and len(bbox) == 4:
                target["layout_box"] = bbox
        else:
            max_idx = max([int(b.get("index") or 0) for b in blocks] + [0])
            blocks.append(
                {
                    "layout_type": layout_type,
                    "layout_box": bbox if isinstance(bbox, list) and len(bbox) == 4 else [0, 0, 10, 10],
                    "content": content,
                    "index": max_idx + 1,
                    "image_path": None,
                    "page_index": page_index,
                }
            )

    pages.sort(key=lambda x: int(x.get("page_index") or 0))
    return pages


def _build_preview_from_ocr_result(ocr_result_data: dict) -> tuple[str, list]:
    """Build markdown/layout preview from incremental ocr_result.json snapshots."""
    pages = ocr_result_data.get("pages", []) or []
    markdown_lines: list[str] = []
    preview_layout: list[dict] = []

    for page in pages:
        for block in page.get("layout", {}).get("blocks", []):
            text = block.get("content", "")
            if block.get("layout_type") == "image":
                img_name = block.get("image_path")
                if img_name:
                    if not os.path.isabs(img_name):
                        img_name = os.path.abspath(img_name)
                    text = (
                        '<div style="text-align: center;"><img '
                        f'src="http://localhost:8000/api/v1/tasks/file?path={img_name}" '
                        'alt="Image"/></div>\n'
                    )
                else:
                    # Manual image overrides may not have cropped image_path yet.
                    text = block.get("content") or "[Manual image region]"

            markdown_lines.append(f"{text}\n")
            preview_layout.append(
                {
                    "block_content": text,
                    "bbox": block.get("layout_box"),
                    "block_id": block.get("index"),
                    "page_index": block.get("page_index"),
                    "layout_type": block.get("layout_type", "text"),
                }
            )

    return "".join(markdown_lines), preview_layout


def _truncate_preview_payload(full_markdown: str, layout: list, max_blocks: int = 1200) -> tuple[str, list, bool, int]:
    """Keep processing-stage responses lightweight to avoid polling timeouts."""
    if not isinstance(layout, list) or len(layout) <= max_blocks:
        return full_markdown, layout if isinstance(layout, list) else [], False, 0

    # Keep latest blocks so UI keeps updating for long PDFs.
    truncated_layout = layout[-max_blocks:]
    truncated_markdown = "".join(f"{b.get('block_content', '')}\n" for b in truncated_layout)
    skipped_blocks = max(0, len(layout) - len(truncated_layout))
    return truncated_markdown, truncated_layout, True, skipped_blocks


@router.post(
    "/upload",
    response_model=ApiResponse[TaskData],
    status_code=status.HTTP_201_CREATED,
)
async def submit_task(
    file: UploadFile = File(..., description="要处理的文件"),
    processing_mode: str = Form("pipeline"),
    priority: int = Form(2, description="1=低,2=正常,3=高,4=紧急"),
    custom_url : str = Form(None, description=""),
    batch_size: int = Form(50, description="OCR batch size (pages per chunk)"),
    output_format: str = Form("markdown"),
):
    """
    提交新任务

    - **file**: 上传文件
    - **processing_mode**: 处理模式，默认pipeline
    - **priority**: 优先级 (1=低, 2=正常, 3=高, 4=紧急)
    - **ocr_config**: OCR配置（JSON字符串，可选）
    - **output_format**: 输出格式，默认markdown
    - **retry_config**: 重试配置（JSON字符串，可选）
    """
    try:
        # 生成document_id
        document_id = str(uuid.uuid4())
        task_id = str(uuid.uuid4())

        parsed_ocr_config = {}
        # 解析配置
        if custom_url is not None:
            parsed_ocr_config["custom_url"] = custom_url
        parsed_ocr_config["batch_size"] = max(1, min(int(batch_size or 50), 500))

        # 保存文件
        save_dir = str(Path(settings.OUTPUT_DIR) / task_id)
        saved_path = await file_upload_handler.save_to_path(
            file=file,
            filename=file.filename,
            upload_dir=save_dir,
        )
        saved_path_obj = Path(saved_path)
        file_size = saved_path_obj.stat().st_size
        file_type = saved_path_obj.suffix.lstrip(".").lower()

        # 提交任务
        task_manager = get_task_manager()
        await task_manager.submit_task(
            task_id=task_id,
            document_id=document_id,
            original_filename=file.filename,
            file_type=file_type,
            file_size=file_size,
            file_path=str(saved_path_obj),
            processing_mode=processing_mode,
            priority=priority,
            ocr_config=parsed_ocr_config,
            output_format=output_format,
        )

        return ApiResponse(
            success=True,
            data={
                "task_id": task_id,
                "document_id": document_id,
                "status": "pending",
                "processing_mode": processing_mode,
                "priority": priority,
                "created_at": datetime.now(UTC).isoformat(),
            },
            message="Task submitted successfully",
        )

    except Exception as e:
        logger.error(f"Failed to submit task: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to submit task: {str(e)}",
        )


@router.get("/file")
async def read_file(path: str, raw: bool = True):
    """
    读取指定路径的文件内容

    默认返回原始文件二进制内容（便于下载 zip、md、json 等文件）。
    设置 raw=false 时，返回 JSON 格式的文件信息（兼容旧行为）。

    - **path**: 文件路径
    - **raw**: 是否返回原始文件，默认 true
    """
    try:
        file_path = Path(path)

        # 检查文件是否存在
        if not file_path.exists():
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"File not found: {path}",
            )

        # 检查是否为文件
        if not file_path.is_file():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Path is not a file: {path}",
            )

        # 获取文件MIME类型
        mime_type, _ = guess_type(file_path.name)
        if mime_type is None:
            mime_type = "application/octet-stream"

        # 读取文件内容
        with open(file_path, "rb") as f:
            content = f.read()

        # 默认直接返回原始文件内容
        if raw:
            disposition = "inline" if mime_type.startswith("image/") else "attachment"
            return Response(
                content=content,
                media_type=mime_type,
                headers={
                    "Content-Disposition": f"{disposition}; filename=\"{file_path.name}\""
                }
            )

        # 兼容模式：返回JSON格式
        try:
            text_content = content.decode("utf-8")
        except UnicodeDecodeError:
            text_content = "(binary file)"

        return ApiResponse(
            success=True,
            data={
                "path": str(file_path.absolute()),
                "filename": file_path.name,
                "size": file_path.stat().st_size,
                "mime_type": mime_type,
                "content": text_content,
            },
            message="File read successfully",
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to read file: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to read file: {str(e)}",
        )


@router.get("/{task_id}", response_model=ApiResponse[dict])
async def get_task_status(
    task_id: str,
    preview_blocks: int = Query(1200, ge=200, le=10000, description="Max preview blocks returned while processing"),
):
    """
    获取任务状态

    - **task_id**: 任务ID
    """
    try:
        task_manager = get_task_manager()
        task_info = await task_manager.get_task_status(task_id)
        manual_overrides = _load_manual_overrides(task_id)

        if not task_info:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Task not found: {task_id}",
            )

        # 如果有 result_file_path，读取并合并内容
        result_file_path = task_info.get("result_file_path")
        result_data = None
        if result_file_path:
            try:
                result_path = Path(result_file_path)
                if result_path.exists():
                    with open(result_path, "r", encoding="utf-8") as f:
                        result_data = json.load(f)
                        logger.info(f"Loaded result data for task {task_id}")
                else:
                    logger.warning(f"Result file not found: {result_file_path}")
            except Exception as e:
                logger.warning(f"Failed to read result file: {e}")

        # Processing-time fallback: read incremental OCR snapshot if present.
        if not result_data:
            try:
                partial_path = Path(settings.OUTPUT_DIR) / task_id / "ocr_result.json"
                if partial_path.exists():
                    with open(partial_path, "r", encoding="utf-8") as f:
                        result_data = json.load(f)
            except Exception as e:
                logger.warning(f"Failed to read partial OCR snapshot: {e}")

        # 构建响应数据
        response_data = {
            "task_id": task_info.get("task_id"),
            "document_id": task_info.get("document_id"),
            "status": task_info.get("status"),
            "progress": task_info.get("progress"),
            "current_step": task_info.get("current_step"),
            "created_at": task_info.get("created_at").isoformat() if task_info.get("created_at") else None,
            "started_at": task_info.get("started_at").isoformat() if task_info.get("started_at") else None,
            "completed_at": task_info.get("completed_at").isoformat() if task_info.get("completed_at") else None,
            "error_message": task_info.get("error_message"),
            "processing_mode": task_info.get("processing_mode"),
            "priority": task_info.get("priority"),
            "retry_count": task_info.get("retry_count"),
            "worker_id": task_info.get("worker_id"),
        }

        db_result = task_info.get("result") or {}

        # 添加结果数据
        if result_data:
            if result_data.get("full_markdown") is not None:
                response_data["metadata"] = result_data.get("metadata")
                response_data["full_markdown"] = result_data.get("full_markdown")
                response_data["layout"] = result_data.get("layout")
            else:
                if manual_overrides:
                    result_data["pages"] = _apply_manual_overrides_to_pages(
                        result_data.get("pages", []) or [],
                        manual_overrides,
                    )
                preview_markdown, preview_layout = _build_preview_from_ocr_result(result_data)
                if task_info.get("status") in ("pending", "processing"):
                    preview_markdown, preview_layout, is_truncated, skipped_blocks = _truncate_preview_payload(
                        preview_markdown,
                        preview_layout,
                        max_blocks=preview_blocks,
                    )
                    response_data["preview_truncated"] = is_truncated
                    response_data["preview_skipped_blocks"] = skipped_blocks
                response_data["full_markdown"] = preview_markdown
                response_data["layout"] = preview_layout
                response_data["processed_pages"] = result_data.get("processed_pages")
                response_data["total_pages"] = result_data.get("total_pages")
                response_data["batch_size"] = result_data.get("batch_size")
                response_data["batch_index"] = result_data.get("batch_index")
            package_info = result_data.get("package") or db_result.get("package") or {}
            package_zip_path = package_info.get("package_zip_path")
            package_dir = package_info.get("package_dir")
            if package_zip_path:
                response_data["package_zip_path"] = package_zip_path
                response_data["package_download_url"] = (
                    f"http://localhost:8000/api/v1/tasks/file?path={package_zip_path}"
                )
            if package_dir:
                response_data["package_dir"] = package_dir

        # Fallback: if merged json doesn't have package info, still serve from DB result
        if not response_data.get("package_zip_path"):
            package_info = db_result.get("package") or {}
            package_zip_path = package_info.get("package_zip_path")
            package_dir = package_info.get("package_dir")
            if package_zip_path:
                response_data["package_zip_path"] = package_zip_path
                response_data["package_download_url"] = (
                    f"http://localhost:8000/api/v1/tasks/file?path={package_zip_path}"
                )
            if package_dir:
                response_data["package_dir"] = package_dir

        # Deterministic fallback from task output directory
        if result_file_path and not response_data.get("package_zip_path"):
            try:
                result_parent = Path(result_file_path).parent
                guessed_zip = result_parent / "complete_output_package.zip"
                guessed_dir = result_parent / "package_output"
                if guessed_zip.exists():
                    response_data["package_zip_path"] = str(guessed_zip)
                    response_data["package_download_url"] = (
                        f"http://localhost:8000/api/v1/tasks/file?path={guessed_zip}"
                    )
                if guessed_dir.exists():
                    response_data["package_dir"] = str(guessed_dir)
            except Exception as e:
                logger.warning(f"Failed to infer package paths for task {task_id}: {e}")

        return ApiResponse(
            success=True,
            data=response_data,
            message="Task status retrieved successfully",
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get task status: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get task status: {str(e)}",
        )


@router.delete("/{task_id}", response_model=ApiResponse[dict])
async def cancel_task(task_id: str):
    """
    取消任务

    - **task_id**: 任务ID
    """
    try:
        task_manager = get_task_manager()
        success = await task_manager.cancel_task(task_id)

        if not success:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Task not found or cannot be cancelled: {task_id}",
            )

        return ApiResponse(
            success=True,
            data={
                "task_id": task_id,
                "status": "cancelled",
            },
            message="Task cancelled successfully",
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to cancel task: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to cancel task: {str(e)}",
        )


@router.get("/", response_model=ApiResponse[dict])
async def list_tasks(status: Optional[str] = None, limit: int = 100, offset: int = 0):
    """
    列出任务

    - **status**: 过滤状态 (pending, processing, completed, failed, cancelled)
    - **limit**: 返回数量限制
    - **offset**: 偏移量
    """
    try:
        task_manager = get_task_manager()
        tasks = await task_manager.list_tasks(status=status, limit=limit, offset=offset)

        return ApiResponse(
            success=True,
            data={
                "tasks": tasks,
                "total": len(tasks),
                "limit": limit,
                "offset": offset,
            },
            message="Tasks retrieved successfully",
        )

    except Exception as e:
        logger.error(f"Failed to list tasks: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to list tasks: {str(e)}",
        )


@router.post("/{task_id}/overrides", response_model=ApiResponse[dict])
async def upsert_manual_overrides(task_id: str, payload: dict):
    """Persist manual OCR overrides for block type/region correction."""
    try:
        incoming = payload.get("overrides") if isinstance(payload, dict) else None
        if not isinstance(incoming, list) or not incoming:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="'overrides' must be a non-empty list",
            )

        replace = bool(payload.get("replace", False)) if isinstance(payload, dict) else False
        existing = [] if replace else _load_manual_overrides(task_id)

        for item in incoming:
            if not isinstance(item, dict):
                continue
            page_index = int(item.get("page_index") or 1)
            block_id = item.get("block_id")
            layout_type = (item.get("layout_type") or "text").lower()
            bbox = item.get("bbox") if isinstance(item.get("bbox"), list) else None
            content = item.get("content") or _default_content_for_type(layout_type)

            normalized = {
                "page_index": page_index,
                "block_id": int(block_id) if block_id is not None else None,
                "layout_type": layout_type,
                "bbox": bbox,
                "content": content,
            }

            replaced = False
            for idx, cur in enumerate(existing):
                if (
                    int(cur.get("page_index") or 0) == page_index
                    and cur.get("block_id") == normalized["block_id"]
                    and normalized["block_id"] is not None
                ):
                    existing[idx] = normalized
                    replaced = True
                    break
            if not replaced:
                existing.append(normalized)

        _save_manual_overrides(task_id, existing)

        return ApiResponse(
            success=True,
            data={"task_id": task_id, "count": len(existing)},
            message="Manual overrides saved",
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to save manual overrides for {task_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to save manual overrides: {str(e)}",
        )
