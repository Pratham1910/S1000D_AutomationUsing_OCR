"""
Add S1000D semantic annotation layer to GLM-OCR JSON output.

Classifies each OCR element as "proced" (procedural) or "descript" (descriptive)
WITHOUT modifying original fields. Appends a "semantic" field to each element.

Usage:
    # Single file
    python semantic_annotate.py result/S1000D.../document_0.json

    # Entire chunk folder (all document_*.json recursively)
    python semantic_annotate.py result/S1000D_Issue_4.2/pages_0001-0050/

    # All chunks in the result folder
    python semantic_annotate.py result/S1000D_Issue_4.2/

    # Use Ollama LLM for uncertain cases (higher accuracy, slower)
    python semantic_annotate.py result/ --llm --llm-model llama3.2

    # Overwrite in place (default: saves as *_semantic.json)
    python semantic_annotate.py result/ --inplace
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# ─── S1000D procedural action verbs ──────────────────────────────────────────
PROCED_VERBS = {
    "remove", "install", "connect", "disconnect", "check", "verify", "ensure",
    "set", "select", "perform", "apply", "close", "open", "turn", "press",
    "push", "pull", "insert", "tighten", "loosen", "adjust", "align", "attach",
    "detach", "activate", "deactivate", "enable", "disable", "start", "stop",
    "examine", "inspect", "measure", "replace", "assemble", "disassemble",
    "clean", "drain", "fill", "lubricate", "torque", "test", "operate",
    "position", "lock", "unlock", "secure", "release", "engage", "disengage",
    "enter", "exit", "switch", "rotate", "slide", "interlock", "monitor",
    "record", "note", "caution", "warn",
}

# Regex patterns that strongly indicate procedural content
PROCED_PATTERNS = [
    r"^\s*\d+[\.\)]\s+[A-Z]",                  # "1. Do this" / "1) Do this"
    r"^\s*[a-z][\.\)]\s+[A-Z]",                # "a. Do this"
    r"^\s*step\s+\d+",                          # "Step 1"
    r"\bmust\s+be\s+(installed|removed|checked|applied|set|replaced|performed|verified|connected|disconnected|secured|tightened|aligned|attached|activated)",
    r"\bshall\s+be\s+(installed|removed|checked|applied|set|replaced|performed|verified|connected|disconnected|secured|tightened|aligned|attached|activated)",
    r"\b(warning|caution|note)\b.*:",           # WARNING: / CAUTION: / NOTE:
    r"torque\s+to\b",                           # "Torque to X Nm"
    r"\bdo\s+not\b",                            # "Do not ..."
]

# Regex patterns that strongly indicate descriptive content
DESCRIPT_PATTERNS = [
    r"\bis\s+used\s+to\b",
    r"\bare\s+used\s+to\b",
    r"\bis\s+defined\s+as\b",
    r"\bprovide[sd]?\b",
    r"\bcontain[sd]?\b",
    r"\binclude[sd]?\b",
    r"\bcovers?\b",
    r"\bthis\s+(section|chapter|module|paragraph|document|data\s+module)\b",
    r"\bthese\s+data\s+modules?\b",
    r"\bthe\s+purpose\s+of\b",
    r"\brefer\s+to\b",
    r"\bdescribe[sd]?\b",
    r"\bexplain[sd]?\b",
    r"\bidentif(y|ies|ied)\b",
    r"\bapplicable\s+to\b",
]


def _score_content(text: str) -> Tuple[str, float]:
    """Return (type, confidence) for a text block using rule-based scoring."""
    if not text or not isinstance(text, str) or len(text.strip()) < 3:
        return "descript", 0.5

    lower = text.lower().strip()
    first_word = lower.split()[0].rstrip(".,;:") if lower.split() else ""

    proced_score = 0.0
    descript_score = 0.0

    # --- Strong procedural signals ---
    # Starts with imperative action verb
    if first_word in PROCED_VERBS:
        proced_score += 0.6

    # Numbered step list
    for pat in PROCED_PATTERNS:
        if re.search(pat, text, re.IGNORECASE | re.MULTILINE):
            proced_score += 0.4
            break

    # Multiple bullet/numbered lines → likely procedural list
    step_lines = re.findall(r"^\s*(\d+[\.\)]|[-•])\s+", text, re.MULTILINE)
    if len(step_lines) >= 2:
        proced_score += 0.3

    # --- Strong descriptive signals ---
    for pat in DESCRIPT_PATTERNS:
        if re.search(pat, text, re.IGNORECASE):
            descript_score += 0.35
            break

    # Long paragraph with no numbered steps → likely descriptive
    if len(text) > 200 and not step_lines:
        descript_score += 0.25

    # S1000D heading patterns (## prefix from OCR)
    if text.strip().startswith("##") or text.strip().startswith("#"):
        descript_score += 0.5

    # Code-like patterns (data module codes: YYYY-...)
    if re.search(r"\bYY[-Y]\b|\b[A-Z0-9]{5,}-[A-Z0-9]{4,}\b", text):
        descript_score += 0.15

    # --- Resolve ---
    if proced_score == 0 and descript_score == 0:
        # Default: long text → descriptive, short → neutral
        t = "descript"
        c = 0.55
    elif proced_score > descript_score:
        t = "proced"
        c = min(0.95, 0.5 + (proced_score - descript_score))
    else:
        t = "descript"
        c = min(0.95, 0.5 + (descript_score - proced_score))

    return t, round(c, 2)


def _build_semantic_proced(text: str, confidence: float) -> Dict:
    """Build semantic block for procedural content."""
    # Extract steps: numbered lines or bullet lines
    lines = text.strip().split("\n")
    steps = []
    step_no = 1
    for line in lines:
        line = line.strip()
        if not line:
            continue
        # Strip leading numbering/bullet
        clean = re.sub(r"^\s*(\d+[\.\)]|[a-z][\.\)]|[-•])\s*", "", line).strip()
        if not clean:
            continue
        # Detect inline warnings
        warnings = []
        if re.search(r"\b(warning|caution)\b", clean, re.IGNORECASE):
            warnings.append(re.search(r"(WARNING|CAUTION)[:\s]+(.+)", clean, re.IGNORECASE)
                            .group(0) if re.search(r"(WARNING|CAUTION)[:\s]+(.+)", clean, re.IGNORECASE) else clean)
            continue
        steps.append({
            "step_no": step_no,
            "action": clean,
            "warnings": warnings,
            "tools": [],
        })
        step_no += 1

    # If no steps parsed, treat full text as single step
    if not steps:
        steps = [{"step_no": 1, "action": text.strip(), "warnings": [], "tools": []}]

    title_match = re.match(r"^#+\s*(.+)", text.strip())
    title = title_match.group(1).strip() if title_match else (steps[0]["action"][:60] + "..." if len(steps[0]["action"]) > 60 else steps[0]["action"])

    return {
        "type": "proced",
        "title": title,
        "structure": {"steps": steps},
        "confidence": confidence,
    }


def _build_semantic_descript(text: str, confidence: float) -> Dict:
    """Build semantic block for descriptive content."""
    # Split into logical paragraphs
    raw_paras = re.split(r"\n{2,}", text.strip())
    paragraphs = [p.strip() for p in raw_paras if p.strip()]
    if not paragraphs:
        paragraphs = [text.strip()]

    # Try to extract title from heading or first sentence
    title_match = re.match(r"^#{1,6}\s*(.+)", text.strip())
    if title_match:
        title = title_match.group(1).strip()
    else:
        first_sent = re.split(r"[.!?]", paragraphs[0])[0].strip()
        title = first_sent[:80] + ("..." if len(first_sent) > 80 else "")

    return {
        "type": "descript",
        "title": title,
        "structure": {"paragraphs": paragraphs},
        "confidence": confidence,
    }


def _llm_classify(text: str, model: str = "llama3.2") -> Tuple[str, float]:
    """Call Ollama LLM for uncertain classification."""
    try:
        import requests
        prompt = (
            "You are an S1000D documentation expert. Classify this text as EXACTLY one of: "
            "'proced' (step-by-step instructions, action verbs, sequential logic) or "
            "'descript' (informational, explanatory, paragraph-based). "
            "Reply with ONLY one word: proced or descript.\n\nText:\n" + text[:500]
        )
        resp = requests.post(
            "http://127.0.0.1:11434/api/generate",
            json={"model": model, "prompt": prompt, "stream": False},
            timeout=30,
        )
        resp.raise_for_status()
        answer = resp.json().get("response", "").strip().lower()
        if "proced" in answer:
            return "proced", 0.85
        return "descript", 0.85
    except Exception:
        return "descript", 0.5


def annotate_element(element: Dict, use_llm: bool = False, llm_model: str = "llama3.2") -> Dict:
    """Add 'semantic' field to a single OCR element. Never modifies original fields."""
    content = element.get("content") or ""
    native_label = element.get("native_label") or ""

    # Shortcut: known structural labels
    if native_label == "paragraph_title":
        sem = _build_semantic_descript(content, 0.95)
        sem["type"] = "descript"
    elif native_label in ("abstract",):
        sem = _build_semantic_descript(content, 0.90)
    elif native_label == "vision_footnote":
        sem = _build_semantic_descript(content, 0.90)
    else:
        sem_type, confidence = _score_content(content)

        # Use LLM for borderline cases (confidence < 0.7)
        if use_llm and confidence < 0.70:
            llm_type, llm_conf = _llm_classify(content, llm_model)
            sem_type = llm_type
            confidence = llm_conf

        sem = (_build_semantic_proced(content, confidence)
               if sem_type == "proced"
               else _build_semantic_descript(content, confidence))

    return {**element, "semantic": sem}


def annotate_file(json_path: Path, use_llm: bool, llm_model: str, inplace: bool) -> Path:
    """Annotate all elements in a JSON file and save result."""
    data = json.loads(json_path.read_text(encoding="utf-8"))

    # data is list of pages; each page is list of elements
    annotated = []
    for page in data:
        if isinstance(page, list):
            annotated.append([annotate_element(el, use_llm, llm_model) for el in page])
        elif isinstance(page, dict):
            # Flat structure (single page without wrapping list)
            annotated.append(annotate_element(page, use_llm, llm_model))
        else:
            annotated.append(page)

    out_path = json_path if inplace else json_path.with_name(json_path.stem + "_semantic.json")
    out_path.write_text(json.dumps(annotated, indent=2, ensure_ascii=False), encoding="utf-8")
    return out_path


def collect_json_files(path: Path) -> List[Path]:
    """Collect all document_*.json files, excluding already-annotated ones."""
    if path.is_file():
        return [path]
    return sorted(
        f for f in path.rglob("*.json")
        if not f.name.endswith("_semantic.json")
        and not f.name.endswith("_model.json")
    )


def main():
    p = argparse.ArgumentParser(description="Add S1000D semantic annotations to GLM-OCR JSON")
    p.add_argument("path", help="JSON file or directory to annotate")
    p.add_argument("--llm", action="store_true", help="Use Ollama LLM for uncertain cases")
    p.add_argument("--llm-model", default="llama3.2", help="Ollama model for LLM mode (default: llama3.2)")
    p.add_argument("--inplace", action="store_true", help="Overwrite original files (default: save as *_semantic.json)")
    args = p.parse_args()

    target = Path(args.path)
    if not target.exists():
        print(f"Error: path not found: {target}")
        sys.exit(1)

    files = collect_json_files(target)
    if not files:
        print("No JSON files found.")
        sys.exit(0)

    print(f"Annotating {len(files)} file(s)  [LLM: {'ON (' + args.llm_model + ')' if args.llm else 'OFF'}]")
    print(f"Mode: {'inplace' if args.inplace else 'save as *_semantic.json'}\n")

    from tqdm import tqdm
    for f in tqdm(files, unit="file", ncols=80):
        try:
            out = annotate_file(f, args.llm, args.llm_model, args.inplace)
            tqdm.write(f"  {f.name} → {out.name}")
        except Exception as e:
            tqdm.write(f"  ERROR {f.name}: {e}")

    print(f"\nDone. Output in: {target if target.is_dir() else target.parent}")


if __name__ == "__main__":
    main()
