"""
Convert GLM-OCR semantic JSON to S1000D Issue 4.2 XML data modules.

Produces one XML file per page, structured as a valid S1000D descriptive or
procedural data module skeleton, derived from the annotated JSON.

Usage:
    # Single semantic JSON file
    python json_to_s1000d_xml.py result/.../document_0_semantic.json

    # Whole chunk folder
    python json_to_s1000d_xml.py result/S1000D_Issue_4.2/pages_0001-0050/

    # All chunks
    python json_to_s1000d_xml.py result/S1000D_Issue_4.2/

    # Supply DM code prefix (overrides auto-detection)
    python json_to_s1000d_xml.py result/ --dm-code MYPRJ-A-00-00-00-00A-040A-A
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from xml.etree import ElementTree as ET
from xml.dom import minidom

# ─── Helpers ─────────────────────────────────────────────────────────────────

DM_CODE_RE = re.compile(
    r"([A-Z0-9]{2,14}-[A-Z0-9]{2,4}-[0-9A-Z]{2}-[0-9A-Z]{2}-[0-9A-Z]{4}"
    r"-[0-9A-Z]{4}-[0-9A-Z]{3,4}[A-Z]-[A-Z])",
    re.IGNORECASE,
)

HEADING_RE = re.compile(r"^#{1,6}\s*(.+)")


def _clean(text: str) -> str:
    """Strip markdown formatting for XML text content."""
    if not text:
        return ""
    # Remove markdown headings
    text = HEADING_RE.sub(r"\1", text)
    # Remove bold/italic
    text = re.sub(r"\*{1,3}(.+?)\*{1,3}", r"\1", text)
    # Remove underline tags
    text = re.sub(r"<u>(.+?)</u>", r"\1", text)
    # Remove inline math markers
    text = re.sub(r"\$\\?[a-zA-Z{}\\_^ ]+\$", "", text)
    # Normalise whitespace
    return " ".join(text.split())


def _detect_dm_code(elements: List[Dict]) -> Optional[str]:
    """Try to extract a data module code from OCR elements."""
    for el in elements:
        content = el.get("content", "") or ""
        m = DM_CODE_RE.search(content)
        if m:
            return m.group(1).upper()
    return None


_STEP_PREFIX_RE = re.compile(r"^(Step|step)\s+\d+\s*[:\.\)]\s*")
_BULLET_RE      = re.compile(r"^[-\u2022]\s+")


def _detect_title(elements: List[Dict]) -> str:
    """Pick the best title from the page elements."""
    for el in elements:
        nl = el.get("native_label", "")
        content = _clean(el.get("content", "") or "")
        if nl in ("doc_title", "paragraph_title") and content:
            return content[:120]
    # Fallback: first markdown heading
    for el in elements:
        content = el.get("content", "") or ""
        m = HEADING_RE.match(content.strip())
        if m:
            return _clean(m.group(1))[:120]
    # Fallback: first short plain-text element that doesn't look like a step/bullet
    for el in elements:
        content = _clean(el.get("content", "") or "")
        if (
            content
            and len(content) <= 150
            and "\n" not in content
            and not _STEP_PREFIX_RE.match(content)
            and not _BULLET_RE.match(content)
        ):
            return content[:120]
    return "Untitled Data Module"


def _dominant_type(elements: List[Dict]) -> str:
    """Return 'proced' or 'descript' based on majority of semantic annotations."""
    counts = {"proced": 0, "descript": 0}
    for el in elements:
        sem = el.get("semantic", {})
        t = sem.get("type", "descript")
        counts[t] = counts.get(t, 0) + 1
    return "proced" if counts["proced"] > counts["descript"] else "descript"


# ─── XML builders ────────────────────────────────────────────────────────────

def _pretty_xml(root: ET.Element) -> str:
    """Return indented XML string with declaration and DOCTYPE."""
    raw = ET.tostring(root, encoding="unicode")
    # minidom for pretty print
    dom = minidom.parseString(raw)
    pretty = dom.toprettyxml(indent="  ", encoding=None)
    # Remove extra blank lines minidom adds
    lines = [l for l in pretty.splitlines() if l.strip()]
    # Replace auto <?xml... with proper declaration + DOCTYPE
    lines[0] = '<?xml version="1.0" encoding="UTF-8"?>'
    lines.insert(1, '<!DOCTYPE dmodule>')
    return "\n".join(lines)


def _make_identification(parent: ET.Element, dm_code: str, title: str, issue_no: str = "001"):
    """Build <identAndStatusSection> block."""
    ias = ET.SubElement(parent, "identAndStatusSection")
    dmAddress = ET.SubElement(ias, "dmAddress")
    dmIdent = ET.SubElement(dmAddress, "dmIdent")

    # Parse dm_code if possible: MODELIDENT-SYSSN-SUBPARA-ASSYUNIT-DISASSY-DISASSYVARIANT-INFOCODE-INFOCODEVARIANT
    parts = dm_code.split("-") if dm_code else []
    # Minimal dmCode element
    dmCode = ET.SubElement(dmIdent, "dmCode")
    dmCode.set("modelIdentCode",      parts[0] if len(parts) > 0 else "UNKWN")
    dmCode.set("systemDiffCode",      parts[1] if len(parts) > 1 else "A")
    dmCode.set("systemCode",          parts[2] if len(parts) > 2 else "00")
    dmCode.set("subSystemCode",       parts[3][:1] if len(parts) > 3 else "0")
    dmCode.set("subSubSystemCode",    parts[3][1:] if len(parts) > 3 and len(parts[3]) > 1 else "0")
    dmCode.set("assyCode",            parts[4] if len(parts) > 4 else "0000")
    dmCode.set("disassyCode",         parts[5][:2] if len(parts) > 5 else "00")
    dmCode.set("disassyCodeVariant",  parts[5][2:] if len(parts) > 5 and len(parts[5]) > 2 else "A")
    dmCode.set("infoCode",            parts[6][:3] if len(parts) > 6 else "040")
    dmCode.set("infoCodeVariant",     parts[6][3:] if len(parts) > 6 and len(parts[6]) > 3 else "A")
    dmCode.set("itemLocationCode",    parts[7] if len(parts) > 7 else "A")

    # S1000D Issue 4.2 requires: dmCode -> language -> issueInfo
    language = ET.SubElement(dmIdent, "language")
    language.set("languageIsoCode", "en")
    language.set("countryIsoCode", "US")

    issueInfo = ET.SubElement(dmIdent, "issueInfo")
    issueInfo.set("issueNumber", issue_no)
    issueInfo.set("inWork", "00")

    dmAddressItems = ET.SubElement(dmAddress, "dmAddressItems")
    issueDate = ET.SubElement(dmAddressItems, "issueDate")
    issueDate.set("year", "2026")
    issueDate.set("month", "04")
    issueDate.set("day", "04")
    dmTitle = ET.SubElement(dmAddressItems, "dmTitle")
    techName = ET.SubElement(dmTitle, "techName")
    techName.text = title

    dmStatus = ET.SubElement(ias, "dmStatus")
    dmStatus.set("issueType", "new")
    security = ET.SubElement(dmStatus, "security")
    security.set("securityClassification", "01")
    responsiblePartnerCompany = ET.SubElement(dmStatus, "responsiblePartnerCompany")
    originator = ET.SubElement(dmStatus, "originator")
    applic = ET.SubElement(dmStatus, "applic")
    displayText = ET.SubElement(applic, "displayText")
    simplePara = ET.SubElement(displayText, "simplePara")
    simplePara.text = "All"
    brexDmRef = ET.SubElement(dmStatus, "brexDmRef")
    dmRef = ET.SubElement(brexDmRef, "dmRef")
    dmRefIdent = ET.SubElement(dmRef, "dmRefIdent")
    brex_code = ET.SubElement(dmRefIdent, "dmCode")
    brex_code.set("modelIdentCode",     "S1000D")
    brex_code.set("systemDiffCode",     "H")
    brex_code.set("systemCode",         "041")
    brex_code.set("subSystemCode",      "1")
    brex_code.set("subSubSystemCode",   "0")
    brex_code.set("assyCode",           "0301")
    brex_code.set("disassyCode",        "00")
    brex_code.set("disassyCodeVariant", "A")
    brex_code.set("infoCode",           "022")
    brex_code.set("infoCodeVariant",    "A")
    brex_code.set("itemLocationCode",   "D")
    qualityAssurance = ET.SubElement(dmStatus, "qualityAssurance")
    ET.SubElement(qualityAssurance, "unverified")


def _heading_depth(raw_content: str, native_label: str) -> Optional[int]:
    """Return 1-based depth of a heading element, or None if not a heading.

    Markdown ##  -> depth = hash count
    Numeric  2   -> depth 1
             2.1 -> depth 2
             2.1.3 -> depth 3
    """
    text = (raw_content or "").strip()
    # Markdown heading
    m = re.match(r"^(#{1,6})\s+", text)
    if m:
        return len(m.group(1))
    # Numeric section heading: starts with digits separated by dots, then space+text
    m = re.match(r"^(\d+(?:\.\d+)*)\s+\S", text)
    if m:
        return m.group(1).count(".") + 1
    # native_label signals
    if native_label == "doc_title":
        return 1
    if native_label == "paragraph_title":
        # Try to infer depth from numeric prefix in content
        m2 = re.match(r"^(\d+(?:\.\d+)*)", text)
        if m2:
            return m2.group(1).count(".") + 1
        return 1
    return None


def _extract_list_items(text: str) -> Tuple[Optional[str], List[str]]:
    """If text is a list block, return (list_type, [item_texts]).

    list_type: 'sequential' (numbered) or 'random' (bullets)
    Returns (None, []) if not a list.
    """
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    bullet_pat = re.compile(r"^[-•]\s+(.+)")
    num_pat    = re.compile(r"^\d+[\.\)]\s+(.+)")
    letter_pat = re.compile(r"^[a-z][\.\)]\s+(.+)")

    bullet_hits  = [bullet_pat.match(l) for l in lines]
    num_hits     = [num_pat.match(l) or letter_pat.match(l) for l in lines]

    # Require at least 2 lines with matching pattern to qualify as a list
    bullet_count = sum(1 for h in bullet_hits if h)
    num_count    = sum(1 for h in num_hits if h)

    if bullet_count >= 2 and bullet_count >= num_count:
        items = [h.group(1).strip() for h in bullet_hits if h]
        return "random", items
    if num_count >= 2:
        items = [h.group(1).strip() for h in num_hits if h]
        return "sequential", items
    return None, []


def _html_table_to_cals(html_str: str, container: ET.Element) -> bool:
    """Parse an HTML table string and emit a proper S1000D CALS <table>.
    Returns True on success, False if no valid table found."""
    from html.parser import HTMLParser

    class _TblParser(HTMLParser):
        def __init__(self):
            super().__init__()
            self.rows: List[List[str]] = []
            self._row: Optional[List[str]] = None
            self._cell: Optional[List[str]] = None

        def handle_starttag(self, tag, attrs):
            if tag == "tr":
                self._row = []
            elif tag in ("td", "th") and self._row is not None:
                self._cell = []

        def handle_endtag(self, tag):
            if tag in ("td", "th") and self._row is not None:
                self._row.append("".join(self._cell or []).strip())
                self._cell = None
            elif tag == "tr" and self._row is not None:
                self.rows.append(self._row)
                self._row = None

        def handle_data(self, data):
            if self._cell is not None:
                self._cell.append(data)

    parser = _TblParser()
    # Feed raw HTML (unescape if needed)
    import html as html_mod
    raw = html_mod.unescape(html_str) if "&lt;" in html_str else html_str
    parser.feed(raw)
    rows = parser.rows
    if not rows:
        return False

    ncols = max((len(r) for r in rows), default=0)
    if ncols == 0:
        return False

    tbl = ET.SubElement(container, "table")
    tbl.set("frame", "all")
    tbl.set("pgwide", "1")
    tbl.set("rowsep", "1")
    tbl.set("colsep", "1")
    tgroup = ET.SubElement(tbl, "tgroup")
    tgroup.set("cols", str(ncols))
    col_w = f"{round(100 / ncols)}*"
    for i in range(1, ncols + 1):
        cs = ET.SubElement(tgroup, "colspec")
        cs.set("colname", f"c{i}")
        cs.set("colwidth", col_w)
        cs.set("align", "left")
    tbody = ET.SubElement(tgroup, "tbody")
    for row_cells in rows:
        row_el = ET.SubElement(tbody, "row")
        for i in range(ncols):
            cell_text = row_cells[i] if i < len(row_cells) else ""
            entry = ET.SubElement(row_el, "entry")
            entry.set("align", "left")
            entry.set("valign", "top")
            entry.set("namest", f"c{i + 1}")
            entry.set("nameend", f"c{i + 1}")
            p = ET.SubElement(entry, "para")
            p.text = cell_text or None
    return True


def _append_content_to(container: ET.Element, content: str, nl: str, el: Dict):
    """Append a para, list, table, or figure to container."""
    if nl == "table":
        raw_content = el.get("content", "") or ""
        # Try to parse embedded HTML table
        if "<table" in raw_content.lower() or "&lt;table" in raw_content:
            if _html_table_to_cals(raw_content, container):
                return
        # Fallback: plain CALS skeleton with text
        tbl = ET.SubElement(container, "table")
        tbl.set("frame", "all")
        tbl.set("pgwide", "1")
        tgroup = ET.SubElement(tbl, "tgroup")
        tgroup.set("cols", "1")
        ET.SubElement(tgroup, "colspec").set("colname", "c1")
        tbody = ET.SubElement(tgroup, "tbody")
        row = ET.SubElement(tbody, "row")
        entry = ET.SubElement(row, "entry")
        entry.set("namest", "c1")
        entry.set("nameend", "c1")
        p = ET.SubElement(entry, "para")
        p.text = content
        return
    if nl == "figure":
        fig = ET.SubElement(container, "figure")
        graphic = ET.SubElement(fig, "graphic")
        graphic.set("infoEntityIdent", el.get("image_path") or "UNKNOWN")
        return
    if nl == "vision_footnote":
        p = ET.SubElement(container, "para")
        p.set("changeType", "add")
        p.text = content
        return

    # Try list detection — list must sit inside a <para> per S1000D 4.2 schema
    list_type, items = _extract_list_items(el.get("content", "") or "")
    if items:
        tag = "sequentialList" if list_type == "sequential" else "randomList"
        wrapper = ET.SubElement(container, "para")
        lst = ET.SubElement(wrapper, tag)
        for item_text in items:
            li = ET.SubElement(lst, "listItem")
            p  = ET.SubElement(li, "para")
            p.text = _clean(item_text)
        return

    # Regular paragraph
    p = ET.SubElement(container, "para")
    p.text = content


def _build_descript_content(parent: ET.Element, elements: List[Dict]):
    """Build <description> with properly nested levelledPara and list support."""
    desc = ET.SubElement(parent, "description")

    # Stack entries: (depth, ET.Element)
    # depth=0 means root <description>
    stack: List[Tuple[int, ET.Element]] = [(0, desc)]

    def _current() -> ET.Element:
        return stack[-1][1]

    for el in elements:
        raw     = el.get("content", "") or ""
        content = _clean(raw)
        nl      = el.get("native_label", "") or ""

        if not content:
            continue

        depth = _heading_depth(raw, nl)

        if depth is not None:
            # Pop stack back to the parent level (depth - 1)
            while len(stack) > 1 and stack[-1][0] >= depth:
                stack.pop()
            parent_el = _current()
            lp = ET.SubElement(parent_el, "levelledPara")
            title_el = ET.SubElement(lp, "title")
            # Strip markdown # prefix and numeric prefix for clean title text
            title_text = HEADING_RE.sub(r"\1", raw).strip()
            title_el.text = _clean(title_text)
            stack.append((depth, lp))
        else:
            _append_content_to(_current(), content, nl, el)


def _build_proced_content(parent: ET.Element, elements: List[Dict]):
    """Build <procedure> content block from procedural elements.

    Smart behaviours:
    - A leading descript element that looks like a section title (no step prefix,
      no bullet) becomes a parent <proceduralStep><title> that wraps all steps.
    - Bullet items immediately following a step are grouped into that step's
      <proceduralStep> as a <randomList> (not emitted as separate steps).
    """
    proc = ET.SubElement(parent, "procedure")
    prelreqs = ET.SubElement(proc, "preliminaryRqmts")
    ET.SubElement(prelreqs, "reqCondGroup")
    ET.SubElement(prelreqs, "reqPersons")
    ET.SubElement(prelreqs, "reqSupportEquips")
    ET.SubElement(prelreqs, "reqSupplies")
    ET.SubElement(prelreqs, "reqSpares")
    ET.SubElement(prelreqs, "reqSafety")

    mainProc = ET.SubElement(proc, "mainProcedure")

    # ── Detect optional leading title element ─────────────────────────────────
    # A leading element is treated as the procedure title when it:
    #   - is classified descript (not a step), OR has a heading native_label
    #   - does NOT start with a step prefix ("Step 1:") or bullet
    #   - is not a markdown heading (those are handled by _heading_depth)
    body_els = list(elements)
    wrapper_ps = mainProc  # default: steps go directly into mainProcedure

    if body_els:
        first = body_els[0]
        fc = _clean(first.get("content", "") or "")
        fn = first.get("native_label", "") or ""
        fsem = first.get("semantic", {}).get("type", "descript")
        is_title = (
            fc
            and not _STEP_PREFIX_RE.match(fc)
            and not _BULLET_RE.match(fc)
            and not HEADING_RE.match((first.get("content", "") or "").strip())
            and (fsem == "descript" or fn in ("doc_title", "paragraph_title"))
        )
        if is_title:
            outer_ps = ET.SubElement(mainProc, "proceduralStep")
            ET.SubElement(outer_ps, "title").text = fc
            wrapper_ps = outer_ps   # nest all remaining steps inside this
            body_els = body_els[1:]

    # ── Group elements: each step optionally followed by bullet items ──────────
    # groups = [ (step_el, [bullet_el, ...]), ... ]
    groups: List[Tuple[Dict, List[Dict]]] = []
    for el in body_els:
        raw_c = (el.get("content") or "").strip()
        if _BULLET_RE.match(raw_c):
            # Attach to last step if one exists
            if groups:
                groups[-1][1].append(el)
            else:
                groups.append((el, []))   # orphan bullet → standalone step
        else:
            groups.append((el, []))

    # ── Emit one <proceduralStep> per group ───────────────────────────────────
    for step_el, bullet_els in groups:
        content = _clean(step_el.get("content", "") or "")
        if not content:
            continue
        nl  = step_el.get("native_label", "") or ""
        sem = step_el.get("semantic", {})

        ps = ET.SubElement(wrapper_ps, "proceduralStep")

        if nl == "paragraph_title" or HEADING_RE.match(step_el.get("content", "") or ""):
            ET.SubElement(ps, "title").text = _clean(
                HEADING_RE.sub(r"\1", step_el.get("content", ""))
            )
        else:
            steps_data = sem.get("structure", {}).get("steps", [])
            if steps_data:
                for sd in steps_data:
                    p = ET.SubElement(ps, "para")
                    p.text = _clean(sd.get("action", ""))
                    for w in sd.get("warnings", []):
                        warn_el = ET.SubElement(ps, "warning")
                        ET.SubElement(warn_el, "warningAndCautionPara").text = _clean(w)
            else:
                ET.SubElement(ps, "para").text = content

        # Trailing bullet items → <para><randomList> inside this step
        if bullet_els:
            wrapper_p = ET.SubElement(ps, "para")
            lst = ET.SubElement(wrapper_p, "randomList")
            for b_el in bullet_els:
                b_raw = (b_el.get("content") or "").strip()
                b_text = _clean(_BULLET_RE.sub("", b_raw))
                li = ET.SubElement(lst, "listItem")
                ET.SubElement(li, "para").text = b_text

    closereqs = ET.SubElement(proc, "closeRqmts")
    ET.SubElement(closereqs, "reqCondGroup")


def page_to_xml(elements: List[Dict], dm_code: str, title: str, page_idx: int) -> str:
    """Convert one page's elements to S1000D Issue 4.2 XML string."""
    dom_type = _dominant_type(elements)

    root = ET.Element("dmodule")
    root.set("xmlns:dc", "http://www.purl.org/dc/elements/1.1/")
    root.set("xmlns:rdf", "http://www.w3.org/1999/02/22-rdf-syntax-ns#")
    root.set("xmlns:xlink", "http://www.w3.org/1999/xlink")
    root.set("xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance")
    root.set("xsi:noNamespaceSchemaLocation",
             "http://www.s1000d.org/S1000D_4-2/xml_schema_flat/descript.xsd"
             if dom_type == "descript"
             else "http://www.s1000d.org/S1000D_4-2/xml_schema_flat/proced.xsd")

    # Identification block
    issue_no = str(page_idx + 1).zfill(3)
    _make_identification(root, dm_code, title, issue_no)

    # Content block
    content_el = ET.SubElement(root, "content")
    if dom_type == "proced":
        _build_proced_content(content_el, elements)
    else:
        _build_descript_content(content_el, elements)

    return _pretty_xml(root)


def process_file(json_path: Path, out_dir: Optional[Path], dm_code_override: Optional[str]):
    """Convert one *_semantic.json to XML files (one per page)."""
    data = json.loads(json_path.read_text(encoding="utf-8"))
    out_base = out_dir or json_path.parent

    results = []
    for page_idx, page in enumerate(data):
        if not isinstance(page, list) or not page:
            continue

        dm_code = dm_code_override or _detect_dm_code(page) or "S1000D-A-00-00-0000-00A-040A-A"
        title = _detect_title(page)

        xml_str = page_to_xml(page, dm_code, title, page_idx)

        stem = json_path.stem.replace("_semantic", "")
        out_name = f"{stem}_page{page_idx:02d}.xml"
        out_path = out_base / out_name
        out_path.write_text(xml_str, encoding="utf-8")
        results.append(out_path)

    return results


def collect_files(path: Path) -> List[Path]:
    if path.is_file():
        return [path]
    files = sorted(path.rglob("*_semantic.json"))
    return files


def main():
    p = argparse.ArgumentParser(description="Convert GLM-OCR semantic JSON -> S1000D Issue 4.2 XML")
    p.add_argument("path", help="Semantic JSON file or directory")
    p.add_argument("--dm-code", default=None, help="Override data module code (auto-detected by default)")
    p.add_argument("--out-dir", default=None, help="Output directory (default: same folder as JSON)")
    args = p.parse_args()

    target = Path(args.path)
    if not target.exists():
        print(f"Error: not found: {target}")
        sys.exit(1)

    files = collect_files(target)
    if not files:
        print("No *_semantic.json files found. Run semantic_annotate.py first.")
        sys.exit(1)

    out_dir = Path(args.out_dir) if args.out_dir else None
    if out_dir:
        out_dir.mkdir(parents=True, exist_ok=True)

    from tqdm import tqdm
    total_xml = 0
    for f in tqdm(files, unit="file", ncols=80, desc="Converting"):
        try:
            written = process_file(f, out_dir, args.dm_code)
            total_xml += len(written)
            tqdm.write(f"  {f.name} -> {len(written)} XML file(s)")
        except Exception as e:
            tqdm.write(f"  ERROR {f.name}: {e}")
            import traceback; traceback.print_exc()

    print(f"\nDone. {total_xml} XML file(s) written.")


if __name__ == "__main__":
    main()
