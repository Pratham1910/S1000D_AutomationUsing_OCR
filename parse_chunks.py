"""
Parse a large PDF in page chunks using glmocr. Automatically loops through all chunks.
The layout model is loaded once and reused across all chunks for speed.

Usage:
    python parse_chunks.py <pdf_path> [--chunk 50] [--start 1] [--end 4000] [--output ./result] [--resume]

Examples:
    python parse_chunks.py S1000D_Issue_4.2.pdf --chunk 50
    python parse_chunks.py S1000D_Issue_4.2.pdf --chunk 50 --resume   # skip already-done chunks
    python parse_chunks.py S1000D_Issue_4.2.pdf --chunk 50 --start 501 --end 1000
"""

import argparse
import sys
import time
from datetime import timedelta
from pathlib import Path

import fitz  # pymupdf
from tqdm import tqdm


def parse_args():
    p = argparse.ArgumentParser(description="Parse large PDF in chunks with glmocr")
    p.add_argument("pdf", help="Path to the PDF file")
    p.add_argument("--chunk", type=int, default=50, help="Pages per chunk (default: 50)")
    p.add_argument("--start", type=int, default=1, help="Start page, 1-indexed (default: 1)")
    p.add_argument("--end", type=int, default=None, help="End page inclusive, 1-indexed (default: last page)")
    p.add_argument("--output", default="./result", help="Output directory (default: ./result)")
    p.add_argument("--resume", action="store_true", help="Skip chunks whose output folder already exists")
    return p.parse_args()


def main():
    args = parse_args()
    pdf_path = Path(args.pdf).resolve()

    if not pdf_path.exists():
        print(f"Error: file not found: {pdf_path}")
        sys.exit(1)

    doc = fitz.open(str(pdf_path))
    total_pages = len(doc)
    start = max(1, args.start)
    end = min(total_pages, args.end) if args.end else total_pages

    # Build chunk list upfront
    chunks = []
    p = start
    while p <= end:
        chunks.append((p, min(p + args.chunk - 1, end)))
        p += args.chunk
    total_chunks = len(chunks)

    print(f"\nPDF : {pdf_path.name}")
    print(f"Pages: {total_pages}  |  Processing: {start}–{end}  |  Chunk size: {args.chunk}  |  Chunks: {total_chunks}")
    print(f"Output: {args.output}")
    if args.resume:
        print("Resume: ON — completed chunks will be skipped")
    print()

    from glmocr import GlmOcr

    skipped = 0
    completed = 0
    chunk_times = []

    # ── Load pipeline ONCE, reuse across all chunks ──────────────────────────
    print("Loading pipeline (layout model + OCR connection)...")
    with GlmOcr() as parser:
        print("Pipeline ready.\n")

        bar = tqdm(chunks, unit="chunk", desc="Overall", ncols=90,
                   bar_format="{l_bar}{bar}| {n_fmt}/{total_fmt} chunks  [{elapsed}<{remaining}]")

        for chunk_num, (chunk_start, chunk_end) in enumerate(bar, 1):
            chunk_label = f"pages_{chunk_start:04d}-{chunk_end:04d}"
            out_dir = Path(args.output) / pdf_path.stem / chunk_label

            bar.set_postfix_str(chunk_label)

            if args.resume and out_dir.exists() and any(out_dir.glob("*.md")):
                tqdm.write(f"  SKIP  [{chunk_num:>3}/{total_chunks}] {chunk_label} (already done)")
                skipped += 1
                continue

            t0 = time.perf_counter()

            sub = fitz.open()
            sub.insert_pdf(doc, from_page=chunk_start - 1, to_page=chunk_end - 1)
            pdf_bytes = sub.tobytes()
            sub.close()

            results = parser.parse(pdf_bytes)
            results.save(output_dir=str(out_dir))

            elapsed = time.perf_counter() - t0
            chunk_times.append(elapsed)
            avg = sum(chunk_times) / len(chunk_times)
            remaining = avg * (total_chunks - chunk_num - skipped)

            tqdm.write(
                f"  DONE  [{chunk_num:>3}/{total_chunks}] {chunk_label}"
                f"  ({elapsed:.0f}s)  ETA: {str(timedelta(seconds=int(remaining)))}"
            )
            completed += 1

    doc.close()
    total_time = sum(chunk_times)
    print(f"\n{'─'*55}")
    print(f"Finished!  Completed: {completed}  Skipped: {skipped}  Total time: {str(timedelta(seconds=int(total_time)))}")
    print(f"Output folder: {Path(args.output) / pdf_path.stem}")


if __name__ == "__main__":
    main()
