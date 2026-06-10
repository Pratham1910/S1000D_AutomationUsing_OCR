"""
结果合并步骤
"""

from typing import Dict, Any, List, Optional, Callable
from pathlib import Path
import json
import os
import shutil
import re
import subprocess
import tempfile
from datetime import datetime, UTC
from xml.sax.saxutils import escape as xml_escape

from app.core.flows.base import ProcessingContext
from app.utils.logger import logger


_ADOC_HEADER_TEMPLATE = """\
:dmc: {dmc}
:dm-type: {dm_type}
:dm-title: {title}
:tech-name: {tech_name}
:revdate: {revdate}
:issue-number: 001
:in-work: 00
:lang: en
:security-classification: 01
:responsible-partner-company: EaseYourWork
:enterprise-code-rpc: 8910X
:originator-enterprise: EaseYourWork
:enterprise-code-originator: 8910X
:applicability: All applicable units and serial numbers.
:brex-dmc: DMC-S1000D-H-041-1-0-0301-00-A-022-A-D
:reason-for-update: Initial draft.

"""


def _make_adoc_header(dm_type: str, title: str) -> str:
    return _ADOC_HEADER_TEMPLATE.format(
        dmc="S1000D-A-00-00-0000-00A-040A-A",
        dm_type=dm_type,
        title=title,
        tech_name=title,
        revdate=datetime.now(UTC).date().isoformat(),
    )


def _slugify_heading(text: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "_", (text or "section").strip()).strip("_").lower()
    return slug or "section"


def _split_markdown_by_heading(md_text: str) -> List[Dict[str, Any]]:
    """Split markdown into heading-based sections.

    Returns list items with keys: title, level, body.
    """
    lines = (md_text or "").splitlines()
    sections: List[Dict[str, Any]] = []
    current: Optional[Dict[str, Any]] = None

    for line in lines:
        m = re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if m:
            if current is not None:
                current["body"] = "\n".join(current["body_lines"]).strip()
                current.pop("body_lines", None)
                sections.append(current)
            current = {
                "title": m.group(2).strip(),
                "level": len(m.group(1)),
                "body_lines": [],
            }
        else:
            if current is None:
                current = {
                    "title": "Introduction",
                    "level": 1,
                    "body_lines": [],
                }
            current["body_lines"].append(line)

    if current is not None:
        current["body"] = "\n".join(current["body_lines"]).strip()
        current.pop("body_lines", None)
        sections.append(current)

    if not sections:
        sections = [{"title": "Document", "level": 1, "body": (md_text or "").strip()}]

    return sections


def _build_package_metadata(context: ProcessingContext, sections: List[Dict[str, Any]]) -> Dict[str, Any]:
    generated_at = datetime.now(UTC).isoformat()
    src_name = Path(context.file_path).name if context.file_path else "unknown"
    return {
        "task_id": context.task_id,
        "document_id": context.document_id,
        "source_filename": src_name,
        "source_file_type": context.file_type,
        "processing_mode": context.processing_mode,
        "output_format": context.output_format,
        "generated_at": generated_at,
        "total_sections": len(sections),
        "total_pages": (context.metadata or {}).get("total_pages", 0),
    }


def _load_manual_overrides(output_dir: str) -> List[Dict[str, Any]]:
    p = Path(output_dir) / "manual_overrides.json"
    if not p.exists():
        return []
    try:
        return json.loads(p.read_text(encoding="utf-8")) or []
    except Exception:
        return []


def _default_content_for_type(layout_type: str) -> str:
    lt = (layout_type or "text").lower()
    if lt == "image":
        return "[Manual image region]"
    if lt == "table":
        return "|===\n| Header 1 | Header 2\n| Cell 1 | Cell 2\n|===\n"
    return "[Manual text region]"


def _apply_manual_overrides_to_pages(pages: List[Dict[str, Any]], overrides: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    if not pages or not overrides:
        return pages

    for ov in overrides:
        page_index = int(ov.get("page_index") or 1)
        block_id = ov.get("block_id")
        layout_type = (ov.get("layout_type") or "text").lower()
        bbox = ov.get("bbox") if isinstance(ov.get("bbox"), list) else None
        content = ov.get("content") or _default_content_for_type(layout_type)

        page_obj = next((p for p in pages if int(p.get("page_index") or 0) == page_index), None)
        if page_obj is None:
            page_obj = {"page_index": page_index, "layout": {"blocks": []}}
            pages.append(page_obj)

        blocks = page_obj.setdefault("layout", {}).setdefault("blocks", [])
        target = None
        if block_id is not None:
            target = next((b for b in blocks if int(b.get("index") or -1) == int(block_id)), None)

        if target:
            target["layout_type"] = layout_type
            target["content"] = content
            if bbox and len(bbox) == 4:
                target["layout_box"] = bbox
        else:
            max_idx = max([int(b.get("index") or 0) for b in blocks] + [0])
            blocks.append(
                {
                    "layout_type": layout_type,
                    "layout_box": bbox if bbox and len(bbox) == 4 else [0, 0, 10, 10],
                    "content": content,
                    "index": max_idx + 1,
                    "image_path": None,
                    "page_index": page_index,
                }
            )

    pages.sort(key=lambda x: int(x.get("page_index") or 0))
    return pages


def _markdown_to_asciidoc(md_text: str) -> str:
    """Best-effort Markdown to AsciiDoc conversion for package output."""
    lines = (md_text or "").splitlines()
    out: List[str] = []
    in_code = False

    for line in lines:
        fence = re.match(r"^```\s*([A-Za-z0-9_\-]*)\s*$", line.strip())
        if fence:
            lang = fence.group(1)
            if not in_code:
                if lang:
                    out.append(f"[source,{lang}]")
                else:
                    out.append("[source]")
                out.append("----")
                in_code = True
            else:
                out.append("----")
                in_code = False
            continue

        if in_code:
            out.append(line)
            continue

        h = re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if h:
            level = len(h.group(1))
            title = h.group(2).strip()
            out.append(f"{'=' * max(1, min(level, 6))} {title}")
            out.append("")
            continue

        # Convert HTML <img> tags (including those wrapped in <div>) to AsciiDoc image macros
        img_tag = re.search(r'<img\s[^>]*src="([^"]*)"[^>]*>', line)
        if img_tag:
            src = img_tag.group(1)
            alt_match = re.search(r'alt="([^"]*)"', line)
            alt = alt_match.group(1) if alt_match else "image"
            out.append(f"image::{src}[{alt}]")
            out.append("")
            continue

        # Skip bare <div> wrapper lines that only contained an img (already handled above)
        if re.match(r'^\s*</?div[^>]*>\s*$', line):
            continue

        converted = line
        converted = re.sub(r"\*\*([^*]+)\*\*", r"*\1*", converted)
        converted = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r"link:\2[\1]", converted)
        converted = re.sub(r"`([^`]+)`", r"+\1+", converted)
        out.append(converted)

    return "\n".join(out).strip() + "\n"


def _markdown_to_asciidoc_pandoc(md_text: str) -> Optional[str]:
    """Convert markdown to asciidoc using pandoc when available."""
    if not shutil.which("pandoc"):
        return None

    tmp_in_path: Optional[str] = None
    tmp_out_path: Optional[str] = None
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as tmp_in:
            tmp_in.write(md_text or "")
            tmp_in_path = tmp_in.name

        with tempfile.NamedTemporaryFile("w", suffix=".adoc", delete=False, encoding="utf-8") as tmp_out:
            tmp_out_path = tmp_out.name

        cmd = [
            "pandoc",
            "-f",
            "markdown",
            "-t",
            "asciidoc",
            "-o",
            tmp_out_path,
            tmp_in_path,
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=60)
        if result.returncode != 0:
            logger.warning(f"pandoc conversion failed: {result.stderr.strip()}")
            return None

        converted = Path(tmp_out_path).read_text(encoding="utf-8")
        return converted if converted.endswith("\n") else f"{converted}\n"
    except Exception as e:
        logger.warning(f"pandoc conversion error: {e}")
        return None
    finally:
        for p in (tmp_in_path, tmp_out_path):
            if p:
                try:
                    os.remove(p)
                except Exception:
                    pass


def _convert_markdown_to_asciidoc(md_text: str) -> str:
    """Prefer pandoc conversion; fallback to built-in converter."""
    pandoc_output = _markdown_to_asciidoc_pandoc(md_text)
    if pandoc_output is not None:
        return pandoc_output
    return _markdown_to_asciidoc(md_text)


def _infer_semantic_type(text: str) -> str:
    t = (text or "").strip().lower()
    if not t:
        return "descript"
    if re.search(r"^\s*(\d+[\.)]|[-*•])\s+", t, re.MULTILINE):
        return "proced"
    if re.search(r"\b(step\s+\d+|install|remove|check|verify|ensure|warning|caution)\b", t):
        return "proced"
    return "descript"


def _build_semantic_json_from_ocr(ocr_data: Dict[str, Any]) -> Dict[str, Any]:
    pages = ocr_data.get("pages", []) or []
    semantic_pages: List[Dict[str, Any]] = []
    counts = {"proced": 0, "descript": 0}

    for page in pages:
        page_blocks: List[Dict[str, Any]] = []
        for block in page.get("layout", {}).get("blocks", []) or []:
            content = block.get("content") or ""
            sem_type = _infer_semantic_type(content)
            counts[sem_type] = counts.get(sem_type, 0) + 1
            page_blocks.append(
                {
                    "index": block.get("index"),
                    "layout_type": block.get("layout_type"),
                    "layout_box": block.get("layout_box"),
                    "content": content,
                    "semantic": {
                        "type": sem_type,
                        "confidence": 0.8,
                    },
                }
            )
        semantic_pages.append(
            {
                "page_index": page.get("page_index"),
                "blocks": page_blocks,
            }
        )

    dominant = "proced" if counts.get("proced", 0) > counts.get("descript", 0) else "descript"
    return {
        "pages": semantic_pages,
        "summary": {
            "counts": counts,
            "dominant_type": dominant,
        },
    }


class MergeResultsStepInput:
    ocr_result_path: str

    def __init__(self, ocr_result_path: str) -> None:
        self.ocr_result_path = ocr_result_path



async def merge_results(
    context: ProcessingContext,
    input: MergeResultsStepInput,
    progress_callback: Optional[Callable[[float, str], None]] = None,
) -> Dict[str, Any]:
    """
    合并OCR结果

    Args:
        context: 处理上下文
        input: MergeResultsStepInput，包含 ocr_result_path
        progress_callback: 进度回调函数

    Returns:
        Dict[str, Any]: 合并后的结果
    """
    task_id = context.task_id
    output_format = context.output_format
    output_dir = context.get_output_dir()
    result_path = input.ocr_result_path
    logger.info(f"[{task_id}] Starting result merge")

    try:
        if progress_callback:
            await progress_callback(0.0, "Initializing merge")

        # 从文件读取OCR结果
        ocr_results = {}
        try:
            with open(result_path, "r", encoding="utf-8") as f:
                result_data = json.load(f)
                ocr_results.update(result_data)
        except Exception as e:
            logger.error(
                f"[{task_id}] Failed to read OCR result from {result_path}: {e}"
            )

        # 根据输出格式进行合并
        manual_overrides = _load_manual_overrides(output_dir)
        if manual_overrides:
            ocr_results["pages"] = _apply_manual_overrides_to_pages(
                ocr_results.get("pages", []) or [],
                manual_overrides,
            )

        md_output_path, json_output_path = await _merge_to_markdown(
            context, ocr_results, output_dir, progress_callback
        )

        if progress_callback:
            await progress_callback(100.0, "Merge completed")

        result = {
            "md_output_path": md_output_path,
            "json_output_path": json_output_path,
            "output_files": [md_output_path, json_output_path],
            "metadata": {
                "format": output_format,
                "total_pages": len(ocr_results.get("pages", [])),
            },
        }

        # Build a complete output package (suite-like structure)
        package_info = await _build_complete_package(
            context=context,
            output_dir=output_dir,
            ocr_result_path=result_path,
            merged_json_path=json_output_path,
            markdown_path=md_output_path,
            progress_callback=progress_callback,
        )
        result["package"] = package_info
        result["output_files"].extend([package_info["package_zip_path"], package_info["manifest_path"]])
        result["metadata"]["package"] = {
            "package_dir": package_info["package_dir"],
            "package_zip_path": package_info["package_zip_path"],
        }

        logger.info(
            f"[{task_id}] Result merge completed: md_output_path:{md_output_path},json_output_path:{json_output_path}"
        )

        return result

    except Exception as e:
        logger.error(f"[{task_id}] Result merge failed: {e}")
        raise


async def _merge_to_markdown(
    context: ProcessingContext,
    ocr_results: Dict[str, Any],
    output_dir: str,
    progress_callback: Optional[Callable[[float, str], None]] = None,
):
    """合并为Markdown格式"""
    pages = ocr_results.get("pages", [])

    markdown_lines = []
    result = {}
    result["metadata"] = context.metadata
    merge_res_layout = []
    total_pages = len(pages)
    for i, page in enumerate(pages):
        # page_num = page.get("page_number", i + 1)
        layout = page.get("layout", {}).get("blocks", [])
        for i, block in enumerate(layout):
            text = block.get("content", "")
            layout_type = block.get("layout_type", "")
            if layout_type == "image":
                img_name = block.get("image_path")
                # 将相对路径转换为绝对路径
                if img_name:
                    if not os.path.isabs(img_name):
                        img_name = os.path.abspath(img_name)
                    text = f'<div style="text-align: center;"><img src="http://localhost:8000/api/v1/tasks/file?path={img_name}" alt="Image"/></div>\n'
                else:
                    text = block.get("content") or "[Manual image region]"
            markdown_lines.append(f"{text}\n")
            merge_res_layout.append(
                {
                    "block_content": text,
                    "bbox": block.get("layout_box"),
                    "block_id": block.get("index"),
                    "page_index": block.get("page_index"),
                }
            )
    if progress_callback:
        progress = 100.0
        await progress_callback(progress, f"Merging page {i + 1}/{total_pages}")
    result["full_markdown"] = "".join(markdown_lines)
    result["layout"] = merge_res_layout
    # 写入文件
    md_output_path = str(Path(output_dir) / "result.md")
    with open(md_output_path, "w", encoding="utf-8") as f:
        f.writelines(markdown_lines)
    json_output_path = str(Path(output_dir) / "merged.json")
    with open(json_output_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    return md_output_path, json_output_path


async def _build_complete_package(
    context: ProcessingContext,
    output_dir: str,
    ocr_result_path: str,
    merged_json_path: str,
    markdown_path: str,
    progress_callback: Optional[Callable[[float, str], None]] = None,
) -> Dict[str, str]:
    """Create a suite-like complete package artifact."""
    task_id = context.task_id
    package_root = Path(output_dir) / "package_output"
    raw_dir = package_root / "01_raw_json"
    semantic_dir = package_root / "02_semantic_json"
    xml_dir = package_root / "03_s1000d_xml"
    adoc_dir = package_root / "04_adoc"

    for d in (raw_dir, semantic_dir, xml_dir, adoc_dir):
        d.mkdir(parents=True, exist_ok=True)

    if progress_callback:
        await progress_callback(92.0, "Building complete package")

    # 01_raw_json
    raw_json_target = raw_dir / "ocr_result.json"
    if Path(ocr_result_path).exists():
        shutil.copy2(ocr_result_path, raw_json_target)

    # 02_semantic_json (placeholder from merged output, same structure used by frontend/backend)
    semantic_json_target = semantic_dir / "semantic_result.json"
    ocr_data_for_semantic: Dict[str, Any] = {}
    try:
        if Path(ocr_result_path).exists():
            ocr_data_for_semantic = json.loads(Path(ocr_result_path).read_text(encoding="utf-8"))
    except Exception as e:
        logger.warning(f"Failed to load OCR data for semantic json: {e}")
    semantic_payload = _build_semantic_json_from_ocr(ocr_data_for_semantic)
    semantic_json_target.write_text(
        json.dumps(semantic_payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    # Build heading-based sections so ADOC/XML are split like suite workflows.
    md_text = Path(markdown_path).read_text(encoding="utf-8") if Path(markdown_path).exists() else ""
    adoc_full_text = _convert_markdown_to_asciidoc(md_text)
    sections = _split_markdown_by_heading(md_text)
    package_meta = _build_package_metadata(context, sections)
    xml_section_files: List[str] = []
    adoc_section_files: List[str] = []
    dm_type = "proced" if semantic_payload.get("summary", {}).get("dominant_type") == "proced" else "descript"

    for idx, sec in enumerate(sections, start=1):
        title = sec["title"]
        level = int(sec.get("level", 1))
        body = (sec.get("body") or "").strip()
        body_adoc = _convert_markdown_to_asciidoc(body).strip()
        slug = _slugify_heading(title)
        base_name = f"{idx:03d}_{slug}"

        adoc_name = f"{base_name}.adoc"
        xml_name = f"{base_name}.xml"
        adoc_path = adoc_dir / adoc_name
        xml_path = xml_dir / xml_name

        adoc_header = _make_adoc_header(dm_type=dm_type, title=title)
        adoc_heading = f"{'=' * max(1, min(level, 5))} {title}\n\n"
        adoc_path.write_text(f"{adoc_header}{adoc_heading}{body_adoc}\n", encoding="utf-8")

        title_xml = xml_escape(str(title))
        content_xml = xml_escape(body)
        source_filename_xml = xml_escape(str(package_meta["source_filename"]))
        source_file_type_xml = xml_escape(str(package_meta["source_file_type"]))
        document_id_xml = xml_escape(str(package_meta["document_id"]))

        xml_content = (
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<s1000dSection issue="4.2" schema="S1000D">\n'
            '  <metadata>\n'
            f'    <taskId>{task_id}</taskId>\n'
            f'    <documentId>{document_id_xml}</documentId>\n'
            f'    <sourceFilename>{source_filename_xml}</sourceFilename>\n'
            f'    <sourceFileType>{source_file_type_xml}</sourceFileType>\n'
            f'    <generatedAt>{package_meta["generated_at"]}</generatedAt>\n'
            '  </metadata>\n'
            f'  <title>{title_xml}</title>\n'
            f'  <level>{level}</level>\n'
            '  <content>\n'
            f'    {content_xml}\n'
            '  </content>\n'
            '</s1000dSection>\n'
        )
        xml_path.write_text(xml_content, encoding="utf-8")

        adoc_section_files.append(str(adoc_path))
        xml_section_files.append(str(xml_path))

    # Section index files
    adoc_index = adoc_dir / "index.adoc"
    adoc_index_lines = [_make_adoc_header(dm_type=dm_type, title="Document Index").rstrip("\n"), "= Document Index", ""]
    for idx, sec in enumerate(sections, start=1):
        slug = _slugify_heading(sec["title"])
        adoc_index_lines.append(f"* xref:{idx:03d}_{slug}.adoc[{sec['title']}]")
    adoc_index.write_text("\n".join(adoc_index_lines) + "\n", encoding="utf-8")

    # Full converted ADOC document using suite-style S1000D header template.
    full_adoc_name = "S1000D_Pipeline_Guide.adoc"
    full_adoc_path = adoc_dir / full_adoc_name
    full_adoc_header = _make_adoc_header(dm_type=dm_type, title="S1000D Pipeline Guide")
    full_adoc_path.write_text(full_adoc_header + adoc_full_text, encoding="utf-8")

    xml_index = xml_dir / "index.xml"
    xml_index_lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<s1000dPackageIndex issue="4.2" schema="S1000D">',
        '  <metadata>',
        f'    <taskId>{task_id}</taskId>',
        f'    <documentId>{xml_escape(str(package_meta["document_id"]))}</documentId>',
        f'    <sourceFilename>{xml_escape(str(package_meta["source_filename"]))}</sourceFilename>',
        f'    <sourceFileType>{xml_escape(str(package_meta["source_file_type"]))}</sourceFileType>',
        f'    <generatedAt>{package_meta["generated_at"]}</generatedAt>',
        '  </metadata>',
    ]
    for idx, sec in enumerate(sections, start=1):
        slug = _slugify_heading(sec["title"])
        sec_title = xml_escape(str(sec["title"]))
        xml_index_lines.append(
            f'  <section file="{idx:03d}_{slug}.xml" title="{sec_title}" level="{sec.get("level", 1)}" />'
        )
    xml_index_lines.append('</s1000dPackageIndex>')
    xml_index.write_text("\n".join(xml_index_lines) + "\n", encoding="utf-8")

    # report + manifest
    report_path = package_root / "conversion_report.txt"
    report_path.write_text(
        "\n".join(
            [
                "Bhishma Complete Output Package",
                f"Task ID: {task_id}",
                f"Generated At (UTC): {datetime.now(UTC).isoformat()}",
                "",
                "Included artifacts:",
                f"- 01_raw_json/ocr_result.json",
                f"- 02_semantic_json/semantic_result.json",
                f"- 03_s1000d_xml/index.xml + section xml files",
                f"- 04_adoc/index.adoc + section adoc files",
                "",
                "Notes:",
                "- semantic_result.json currently mirrors merged result structure.",
                "- ADOC and XML are split heading-wise from markdown sections.",
            ]
        ),
        encoding="utf-8",
    )

    manifest_path = package_root / "manifest.json"
    manifest = {
        "task_id": task_id,
        "generated_at": datetime.now(UTC).isoformat(),
        "s1000d_metadata": package_meta,
        "files": {
            "raw_json": str(raw_json_target),
            "semantic_json": str(semantic_json_target),
            "adoc_full": str(full_adoc_path),
            "xml_index": str(xml_index),
            "xml_sections": xml_section_files,
            "adoc_index": str(adoc_index),
            "adoc_sections": adoc_section_files,
            "report": str(report_path),
        },
        "sections": [
            {
                "title": sec["title"],
                "level": sec.get("level", 1),
                "slug": _slugify_heading(sec["title"]),
            }
            for sec in sections
        ],
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    zip_base = Path(output_dir) / "complete_output_package"
    zip_path = shutil.make_archive(str(zip_base), "zip", root_dir=str(package_root))

    if progress_callback:
        await progress_callback(98.0, "Complete package ready")

    return {
        "package_dir": str(package_root),
        "package_zip_path": str(zip_path),
        "manifest_path": str(manifest_path),
        "report_path": str(report_path),
    }
