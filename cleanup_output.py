"""
cleanup_output.py — Post-process existing converter output directories.

Strips residual ```markdown / ``` fence artifacts from .adoc and .md files
that were generated before the fix was applied.

Usage:
    python cleanup_output.py <output_root>
    python cleanup_output.py C:/path/to/output_folder
    python cleanup_output.py .                   # current directory

It rewrites in-place; originals are not backed up by default.
Pass --backup to keep .bak copies.
"""

import re
import sys
import shutil
from pathlib import Path

# ---------------------------------------------------------------------------
# Same regexes used in the converter
# ---------------------------------------------------------------------------
_MD_FENCE_RE    = re.compile(r"^\s*```(?:markdown|md)?\s*\n(.*?)\n?\s*```\s*$", re.DOTALL)
_FENCE_BLOCK_RE = re.compile(r"```[\w+-]*[ \t]*\n(.*?)\n?[ \t]*```", re.DOTALL)
_SPLIT_HEADER_RE = re.compile(r"```[ \t]*\r?\n[ \t]*(markdown|md)[ \t]*\r?\n", re.IGNORECASE)
_BARE_LANG_LINE_RE = re.compile(r"^[ \t]*(markdown|md)[ \t]*$", re.MULTILINE | re.IGNORECASE)
_ADOC_BARE_FENCE_RE = re.compile(r"^[ \t]*```[\w+-]*[ \t]*$", re.MULTILINE)
_CJK_RE = re.compile(r'[一-鿿㐀-䶿　-〿＀-￯぀-ゟ゠-ヿ]')
_PUNCT_ONLY_RE = re.compile(r'^[\s\W]*$')


def _is_cjk_artifact(line: str) -> bool:
    s = line.strip()
    if not s:
        return False
    cjk_count = len(_CJK_RE.findall(s))
    non_ws = len(re.sub(r'\s', '', s))
    return non_ws > 0 and cjk_count / non_ws >= 0.4


def strip_md_fences(text: str) -> str:
    if not text or "```" not in text:
        if re.search(r"^[ \t]*(?:markdown|md)[ \t]*$", text, re.MULTILINE | re.IGNORECASE):
            text = _BARE_LANG_LINE_RE.sub("", text)
            return re.sub(r'\n{3,}', '\n\n', text).strip()
        return text

    s = text.strip()
    s = _SPLIT_HEADER_RE.sub("```markdown\n", s)

    m = _MD_FENCE_RE.match(s)
    if m:
        inner = m.group(1).strip()
        inner = _BARE_LANG_LINE_RE.sub("", inner)
        inner = re.sub(r'\n{3,}', '\n\n', inner).strip()
        if "```" not in inner:
            return inner
        s = inner

    for blk in list(_FENCE_BLOCK_RE.finditer(s)):
        inner = blk.group(1).strip()
        inner_cmp = re.sub(r'^(?:markdown|md)\s*\n?', '', inner, flags=re.IGNORECASE).strip()
        outside = (s[:blk.start()] + s[blk.end():]).strip()
        if not inner_cmp or inner_cmp in outside:
            s = s.replace(blk.group(0), "", 1)
        else:
            s = s.replace(blk.group(0), inner_cmp, 1)

    if "```" not in s:
        s = _BARE_LANG_LINE_RE.sub("", s)
        return re.sub(r'\n{3,}', '\n\n', s).strip()

    out_lines = []
    for ln in s.splitlines(keepends=True):
        if ln.strip().startswith("```"):
            continue
        out_lines.append(ln)
    s = "".join(out_lines)

    s = _BARE_LANG_LINE_RE.sub("", s)
    return re.sub(r'\n{3,}', '\n\n', s).strip()


def clean_adoc_text(text: str) -> str:
    if not text:
        return text
    text = strip_md_fences(text)
    text = _ADOC_BARE_FENCE_RE.sub("", text)
    text = _BARE_LANG_LINE_RE.sub("", text)
    return re.sub(r'\n{3,}', '\n\n', text).strip()


_PUNCT_ONLY_RE = re.compile(r'^[\s\W]*$')


def dedup_lines(lines, window: int = 50):
    """Remove near-duplicate, punctuation-only, and CJK-artifact lines."""
    def _norm(s: str) -> str:
        return re.sub(r'[^a-z0-9]', '', s.lower())

    result, seen = [], []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            result.append(line)
            continue
        if _PUNCT_ONLY_RE.match(stripped):
            continue
        if _is_cjk_artifact(stripped):
            continue
        n = _norm(stripped)
        if len(n) > 5 and n in seen:
            continue
        result.append(line)
        if n:
            seen.append(n)
            if len(seen) > window:
                seen.pop(0)
    return result


def process_file(path: Path, backup: bool) -> bool:
    original = path.read_text(encoding="utf-8", errors="replace")
    if path.suffix == ".adoc":
        cleaned = clean_adoc_text(original)
        cleaned = "\n".join(dedup_lines(cleaned.splitlines()))
    else:
        cleaned = strip_md_fences(original)
        cleaned = "\n".join(dedup_lines(cleaned.splitlines()))

    if cleaned == original.strip():
        return False  # nothing changed

    if backup:
        shutil.copy2(path, path.with_suffix(path.suffix + ".bak"))

    path.write_text(cleaned + "\n", encoding="utf-8")
    return True


def main():
    args = sys.argv[1:]
    backup = "--backup" in args
    roots = [Path(a) for a in args if not a.startswith("--")]
    if not roots:
        roots = [Path(".")]

    total = changed = 0
    for root in roots:
        for ext in ("*.adoc", "*.md"):
            for p in root.rglob(ext):
                total += 1
                try:
                    if process_file(p, backup):
                        changed += 1
                        print(f"  cleaned: {p}")
                except Exception as exc:
                    print(f"  ERROR {p}: {exc}")

    print(f"\nDone — {changed}/{total} file(s) modified.")


if __name__ == "__main__":
    main()
