import os
import sys
import subprocess
import glob
import tkinter as tk
from tkinter import scrolledtext, font, filedialog, messagebox
from tkinter import ttk
import threading
import re


# --- Helper to locate bundled resources (works for PyInstaller + dev) ---
def resource_path(relative_path):
    """Get absolute path to resource, works for dev and for PyInstaller"""
    if hasattr(sys, "_MEIPASS"):
        return os.path.join(sys._MEIPASS, relative_path)
    return os.path.join(os.path.abspath("."), relative_path)


# --- Configuration: Ruby scripts are bundled in 'Ruby' folder ---
RUBY_CONVERTER_SCRIPT_STANDARD = resource_path(os.path.join("Ruby", "s1000d1.rb"))
RUBY_CONVERTER_SCRIPT_FAULT    = resource_path(os.path.join("Ruby", "s1000d2.rb"))
RUBY_CONVERTER_SCRIPT_SCHED    = resource_path(os.path.join("Ruby", "s1000d_sched.rb"))
LUA_FILTER_PATH                = resource_path(os.path.join("Ruby", "s1000d_md_styles.lua"))

# ---------------------------------------------------------------------------
# All 21 S1000D data module schema types (Issue 4.2 / 6.0)
# ---------------------------------------------------------------------------
S1000D_DM_TYPES = [
    "descript",
    "procedure",
    "fault",
    "proced",
    "sched",
    "container",
    "crew",
    "sb",
    "pim",
    "chkl",
    "learning",
    "frontmatter",
    "appliccrossreftable",
    "condcrossreftable",
    "functionalitem",
    "partrepository",
    "illustratedpartscatalog",
    "wrngdata",
    "comrepository",
    "brex",
    "techrep",
]

DM_TYPE_DESCRIPTIONS = {
    "descript":                "Descriptive — system/component description",
    "procedure":               "Procedural — maintenance/operating procedures",
    "fault":                   "Fault isolation data module",
    "proced":                  "Procedural (alternate format)",
    "sched":                   "Scheduled maintenance tasks",
    "container":               "Container — groups related DMs",
    "crew":                    "Crew / operator information",
    "sb":                      "Service bulletin",
    "pim":                     "Preliminary information",
    "chkl":                    "Checklist",
    "learning":                "Learning / CBT training module",
    "frontmatter":             "Front matter (title page, TOC)",
    "appliccrossreftable":     "Applicability cross-reference table",
    "condcrossreftable":       "Condition cross-reference table",
    "functionalitem":          "Functional item repository",
    "partrepository":          "Parts repository",
    "illustratedpartscatalog": "Illustrated parts catalog (IPC)",
    "wrngdata":                "Wiring data",
    "comrepository":           "Comments repository",
    "brex":                    "Business rules exchange",
    "techrep":                 "Technical report",
}

# --- Map each DM type to its Ruby backend script ---
RUBY_SCRIPT_MAP = {
    "fault":                  RUBY_CONVERTER_SCRIPT_FAULT,
    "sched":                  RUBY_CONVERTER_SCRIPT_SCHED,
    "schedule":               RUBY_CONVERTER_SCRIPT_SCHED,
    "scheduled":              RUBY_CONVERTER_SCRIPT_SCHED,
    "scheduled maintenance":  RUBY_CONVERTER_SCRIPT_SCHED,
}
# All other types fall back to the standard script.

# ---------------------------------------------------------------------------
# Lua filter — Markdown convention:
#   *italic*  -> AsciiDoc cross-reference  <<target>>
#   **bold**  -> AsciiDoc block anchor     [[id]]
# ---------------------------------------------------------------------------
LUA_FILTER_CONTENT = r"""
-- Pandoc Lua filter: Markdown -> S1000D AsciiDoc
-- *italic* => <<cross-reference>>
-- **bold** => [[anchor-id]]

function Emph(el)
  local content_text = pandoc.utils.stringify(el.content)
  return pandoc.RawInline("asciidoc", "<<" .. content_text .. ">>")
end

function Strong(el)
  local content_text = pandoc.utils.stringify(el.content)
  return pandoc.RawInline("asciidoc", "[[" .. content_text .. "]]")
end
"""


# ---------------------------------------------------------------------------
# Header templates for all 21 S1000D schemas
# ---------------------------------------------------------------------------
def get_header_content(final_dmc, dm_type):
    """Return the AsciiDoc attribute header + skeleton sections for any DM type."""
    base = (
        f":dmc: {final_dmc}\n"
        f":dm-type: {dm_type}\n"
        f":tech-name: Sample System Widget Task\n"
        f":revdate: 2025-09-02\n"
        f":issue-number: 001\n"
        f":in-work: 00\n"
        f":lang: en\n"
        f":security-classification: 01\n"
        f":responsible-partner-company: EaseYourWork\n"
        f":enterprise-code-rpc: 8910X\n"
        f":originator-enterprise: EaseYourWork\n"
        f":enterprise-code-originator: 8910X\n"
        f":applicability: All applicable units and serial numbers.\n"
        f":brex-dmc: DMC-S1000D-H-041-1-0-0301-00-A-022-A-D\n"
        f":reason-for-update: Initial draft for demonstration purposes.\n"
    )

    type_blocks = {
        "descript": (
            ":dm-title: Component Description\n\n"
            "[[description]]\n== Description\n\n"
        ),
        "procedure": (
            ":dm-title: Maintenance Procedure\n\n"
            "[[prelim_reqs]]\n== Preliminary Requirements\n\n"
            "[[main_proc]]\n== Procedure\n"
            ". Perform maintenance step\n\n"
        ),
        "fault": (
            ":dm-title: Fault Isolation\n\n"
            "[[fault_reporting]]\n== Fault Reporting\n\n"
            "[[fault_isolation]]\n== Fault Isolation\n"
            ". Check fault indicator\n\n"
        ),
        "proced": (
            ":dm-title: Procedural Data Module\n\n"
            "[[prelim_reqs]]\n== Preliminary Requirements\n\n"
            "[[procedure]]\n== Procedure\n\n"
        ),
        "sched": (
            ":dm-title: Scheduled Maintenance Tasks\n\n"
            "[[prelim_reqs]]\n== Preliminary Requirements\n\n"
            "[[sched_tasks]]\n== Scheduled Maintenance Tasks\n"
            ". Perform a general scheduled maintenance check\n"
            ". Inspect and clean critical components\n\n"
        ),
        "container": (
            ":dm-title: Container Data Module\n\n"
            "[[container_content]]\n== Container Content\n\n"
        ),
        "crew": (
            ":dm-title: Crew/Operator Information\n\n"
            "[[crew_roles]]\n== Crew Roles\n\n"
            "[[crew_procedures]]\n== Crew Procedures\n\n"
        ),
        "sb": (
            ":dm-title: Service Bulletin\n\n"
            "[[sb_planning]]\n== Planning Information\n\n"
            "[[sb_procedure]]\n== Service Bulletin Procedure\n\n"
        ),
        "pim": (
            ":dm-title: Preliminary Information\n\n"
            "[[prelim_info]]\n== Preliminary Information\n\n"
        ),
        "chkl": (
            ":dm-title: Maintenance Checklist\n\n"
            "[[checklist_items]]\n== Checklist Items\n\n"
            ". Inspect component A\n"
            ". Verify torque values\n\n"
        ),
        "learning": (
            ":dm-title: Learning/Training Module\n\n"
            "[[learning_objectives]]\n== Learning Objectives\n\n"
            "[[content]]\n== Content\n\n"
        ),
        "frontmatter": (
            ":dm-title: Front Matter\n\n"
            "[[title_page]]\n== Title Page\n\n"
            "[[table_of_contents]]\n== Table of Contents\n\n"
        ),
        "appliccrossreftable": (
            ":dm-title: Applicability Cross-Reference Table\n\n"
            "[[applicability]]\n== Applicability Cross-Reference\n\n"
        ),
        "condcrossreftable": (
            ":dm-title: Condition Cross-Reference Table\n\n"
            "[[conditions]]\n== Condition Cross-Reference\n\n"
        ),
        "functionalitem": (
            ":dm-title: Functional Item Repository\n\n"
            "[[functional_items]]\n== Functional Items\n\n"
        ),
        "partrepository": (
            ":dm-title: Parts Repository\n\n"
            "[[parts]]\n== Parts List\n\n"
        ),
        "illustratedpartscatalog": (
            ":dm-title: Illustrated Parts Catalog\n\n"
            "[[ipc_general]]\n== General\n\n"
            "[[ipc_parts]]\n== Illustrated Parts\n\n"
        ),
        "wrngdata": (
            ":dm-title: Wiring Data\n\n"
            "[[wiring_list]]\n== Wiring List\n\n"
            "[[wiring_diagram]]\n== Wiring Diagram\n\n"
        ),
        "comrepository": (
            ":dm-title: Comments Repository\n\n"
            "[[comments]]\n== Comments\n\n"
        ),
        "brex": (
            ":dm-title: Business Rules Exchange\n\n"
            "[[brex_rules]]\n== Business Rules\n\n"
            "[[brex_applicability]]\n== Applicability\n\n"
        ),
        "techrep": (
            ":dm-title: Technical Report\n\n"
            "[[summary]]\n== Summary\n\n"
            "[[technical_details]]\n== Technical Details\n\n"
        ),
    }

    type_block = type_blocks.get(
        dm_type,
        ":dm-title: Technical Document\n\n[[content]]\n== Content\n\n",
    )
    return base + type_block


# ---------------------------------------------------------------------------
# Backend conversion logic
# ---------------------------------------------------------------------------

def cleanup_adoc_string(adoc_content_string, log_func):
    """
    Applies general cleanup and fixes to the generated AsciiDoc content
    (in-memory string).
    """
    log_func("    Applying in-memory cleanup logic...")
    try:
        content = adoc_content_string

        # 1. Remove isolated empty section headers
        cleaned_content = re.sub(r"^\s*=+?\s*$", r"", content, flags=re.MULTILINE)

        # 2. Remove unwanted soft line breaks ('+') generated by Pandoc
        cleaned_content = re.sub(r",\s*\n\s*\+\s*\n", r",\n", cleaned_content)
        cleaned_content = re.sub(r"([^\n,])\n\s*\+\s*\n", r"\1\n", cleaned_content)
        cleaned_content = re.sub(
            r"(.+?)\s*\+\s*$", r"\1", cleaned_content, flags=re.MULTILINE
        )

        # 3a. Remove misplaced dots before section headers
        cleaned_content = re.sub(
            r"^\s*\.(\=+)\s+", r"\1 ", cleaned_content, flags=re.MULTILINE
        )
        # 3b. Remove misplaced dots before list attributes
        cleaned_content = re.sub(
            r"^\s*\.(\[.+?\])", r"\1", cleaned_content, flags=re.MULTILINE
        )
        # 3c. Fix table header marker
        cleaned_content = re.sub(
            r"^\s*\.\|===", r"|===", cleaned_content, flags=re.MULTILINE
        )
        # 3d. Remove [arabic] / [arabic, start=X] attributes
        cleaned_content = re.sub(
            r"\[arabic(\s*,\s*start=\d+)?\]\s*",
            r"",
            cleaned_content,
            flags=re.MULTILINE,
        )

        # 4. Catch standalone dot on a line that should lead list content
        cleaned_content = re.sub(
            r"^\s*\.\s*$\n([A-Z0-9\[].*)", r". \1", cleaned_content, flags=re.MULTILINE
        )
        cleaned_content = re.sub(
            r"^\s*\.\s+Sub-step", r".. Sub-step", cleaned_content, flags=re.MULTILINE
        )

        # 5. General cleanup
        cleaned_content = re.sub(
            r"\{\s*empty\s*\}", r"", cleaned_content, flags=re.MULTILINE
        )
        cleaned_content = re.sub(
            r"^\s*\{plus\}\s*$", r"+", cleaned_content, flags=re.MULTILINE
        )
        cleaned_content = re.sub(
            r"^\s*____\s*$", r"", cleaned_content, flags=re.MULTILINE
        )
        cleaned_content = re.sub(r"(--\n)\s+", r"\1", cleaned_content)
        cleaned_content = re.sub(r"\s+(\n--)", r"\1", cleaned_content)

        # 6. Cross-reference tidying
        cleaned_content = re.sub(r"<<\s*(.+?)\s*>>", r"<<\1>>", cleaned_content)
        cleaned_content = re.sub(
            r"<<(.*)([\.\,\?\!\:\;])>>", r"<<\1>>\2", cleaned_content
        )

        # 7. Join multi-line attribute blocks into a single line
        lines = cleaned_content.splitlines()
        rebuilt_lines = []
        in_attribute_block = False
        for line in lines:
            stripped_line = line.strip()
            if stripped_line.startswith("[") and not stripped_line.endswith("]"):
                in_attribute_block = True
                rebuilt_lines.append(line.rstrip())
            elif in_attribute_block:
                rebuilt_lines[-1] += " " + stripped_line.replace("`", "")
                if stripped_line.endswith("]"):
                    in_attribute_block = False
            else:
                rebuilt_lines.append(line)
        cleaned_content = "\n".join(rebuilt_lines)

        # 8. Normalize spacing around thematic breaks
        cleaned_content = re.sub(
            r"\s*^\s*-{3,}\s*$\s*", r"\n\n---\n\n", cleaned_content, flags=re.MULTILINE
        )

        # 9. Anchor ID fixes
        cleaned_content = re.sub(r"([^\n])(\[\[.+?\]\])", r"\1\n\2", cleaned_content)
        cleaned_content = re.sub(
            r"(--\s*\n)(\[\[.+?\]\])", r"\1\n\2", cleaned_content, flags=re.MULTILINE
        )
        cleaned_content = re.sub(r"(\[\[.+?\]\])([^\n])", r"\1\n\2", cleaned_content)

        # 10. Ensure exactly one space after list markers (. or ..)
        cleaned_content = re.sub(
            r"^((\.{1,2}))\s*(?=\S)",
            r"\1 ",
            cleaned_content,
            flags=re.MULTILINE,
        )

        # 11. Collapse excess blank lines
        cleaned_content = re.sub(r"\n\s*\n", r"\n\n", cleaned_content)

        return cleaned_content

    except Exception as e:
        log_func(f"    ERROR: Failed to apply cleanup.\n    Details: {e}")
        return adoc_content_string


def process_dmc_filename(filename, log_func):
    """Converts a standardised DMC filename to the structured S1000D format."""
    if not filename.startswith("DMC-"):
        return filename

    base_code = filename[4:]
    parts = base_code.split("-")

    if len(parts) == 8:
        p1, p2, p3, p4, p5, p6, p7, p8 = parts
        subSystemCode      = p4[0] if len(p4) > 0 else ""
        subSubSystemCode   = p4[1] if len(p4) > 1 else ""
        disassyCode        = p6[:-1] if len(p6) > 0 else ""
        disassyCodeVariant = p6[-1]  if len(p6) > 0 else ""
        infoCode_raw       = p7[:-1] if len(p7) > 0 else ""
        infoCodeVariant    = p7[-1]  if len(p7) > 0 else ""
        infoCode           = infoCode_raw.zfill(3)
        final_parts = [
            p1, p2, p3,
            subSystemCode, subSubSystemCode,
            p5,
            disassyCode, disassyCodeVariant,
            infoCode, infoCodeVariant,
            p8,
        ]
        return "DMC-" + "-".join(final_parts)
    return filename


def ensure_lua_filter_exists(log_func):
    """Writes the Lua filter content to the expected file path."""
    try:
        os.makedirs(os.path.dirname(LUA_FILTER_PATH), exist_ok=True)
        with open(LUA_FILTER_PATH, "w", encoding="utf-8") as f:
            f.write(LUA_FILTER_CONTENT)
        log_func(f"    Info: Lua filter written to '{os.path.basename(LUA_FILTER_PATH)}'.")
        return True
    except Exception as e:
        log_func(f"    ERROR: Could not write Lua filter.\n    Details: {e}")
        return False


# ---------------------------------------------------------------------------
# Step 1 — Markdown → AsciiDoc  (in-memory, via Pandoc + Lua filter)
# ---------------------------------------------------------------------------

def convert_step1(input_dir, log_func, dm_type):
    """
    Reads every .md / .markdown file in *input_dir*, converts each to an
    AsciiDoc string using Pandoc + the S1000D Lua filter, prepends the
    appropriate S1000D header skeleton, then applies post-processing cleanup.

    Returns a dict  {filename_no_ext: cleaned_adoc_string}
    or None on fatal error.
    """
    log_func("Starting Step 1: Markdown → AsciiDoc (via Pandoc + Lua filter)...")

    if not ensure_lua_filter_exists(log_func):
        return None

    md_files = (
        glob.glob(os.path.join(input_dir, "*.md"))
        + glob.glob(os.path.join(input_dir, "*.markdown"))
    )
    if not md_files:
        log_func("  No Markdown files (.md / .markdown) found. Skipping Step 1.")
        return {}

    processed = {}

    for md_file in md_files:
        filename_with_ext = os.path.basename(md_file)
        log_func(f'  - Processing: "{filename_with_ext}"')
        filename_no_ext = os.path.splitext(filename_with_ext)[0]

        if filename_no_ext.startswith("~$"):
            log_func("    ...SKIPPED (temporary file).")
            continue

        final_dmc    = process_dmc_filename(filename_no_ext, log_func)
        header_block = get_header_content(final_dmc, dm_type)

        try:
            command = [
                "pandoc",
                md_file,
                "--lua-filter", LUA_FILTER_PATH,
                "-t", "asciidoc",
            ]

            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                check=True,
                encoding="utf-8",
                shell=True,
            )
            adoc_body = result.stdout

            # Inline post-Pandoc sanitisation
            adoc_body = re.sub(r"\+\+(.*?)\+\+", r"\1", adoc_body)
            adoc_body = re.sub(
                r"^(\s*image):", r"\1::", adoc_body, flags=re.MULTILINE
            )

            full_adoc = header_block + adoc_body
            cleaned   = cleanup_adoc_string(full_adoc, log_func)

            processed[filename_no_ext] = cleaned

        except FileNotFoundError:
            log_func(
                "\nERROR: Pandoc was not found. Ensure Pandoc is installed and on your PATH."
            )
            return None
        except subprocess.CalledProcessError as e:
            log_func(
                f"\nERROR: Pandoc failed for '{filename_with_ext}'.\n  Details:\n{e.stderr}"
            )
            return None
        except Exception as e:
            log_func(
                f"\nUnexpected error in Step 1 for '{filename_with_ext}': {e}"
            )
            return None

    return processed


# ---------------------------------------------------------------------------
# Step 2 — AsciiDoc → S1000D XML  (via Asciidoctor + Ruby backend)
# ---------------------------------------------------------------------------

def convert_step2(adoc_contents_dict, final_dir, log_func, dm_type):
    """
    Passes each in-memory AsciiDoc string to Asciidoctor via stdin,
    selecting the correct Ruby backend for the given DM type, and writes
    the resulting XML to *final_dir*.

    Supports all 21 S1000D schemas via RUBY_SCRIPT_MAP (falls back to the
    standard script for types not explicitly mapped).
    """
    log_func("\nStarting Step 2: AsciiDoc → S1000D XML (Asciidoctor Ruby backend)...")
    os.makedirs(final_dir, exist_ok=True)

    dm_type_key     = (dm_type or "").strip().lower()
    ruby_script_path = RUBY_SCRIPT_MAP.get(dm_type_key, RUBY_CONVERTER_SCRIPT_STANDARD)

    if not adoc_contents_dict:
        log_func("  No AsciiDoc content to process. Skipping Step 2.")
        return True

    if not os.path.exists(ruby_script_path):
        log_func(
            f"ERROR: Ruby backend script not found: {ruby_script_path}\n"
            f"  Ensure the correct .rb file is present in the 'Ruby' folder."
        )
        return False

    for file_name_no_ext, adoc_string in adoc_contents_dict.items():
        log_func(f"  - Generating XML for: {file_name_no_ext}")
        output_file = os.path.join(final_dir, f"{file_name_no_ext}.xml")

        command = [
            "asciidoctor",
            "--trace",
            "-r", ruby_script_path,
            "-b", "s1000d",
            "-",          # read from stdin
            "-o", output_file,
        ]

        try:
            subprocess.run(
                command,
                input=adoc_string,
                check=True,
                capture_output=True,
                text=True,
                encoding="utf-8",
                shell=True,
            )
        except FileNotFoundError:
            log_func(
                "ERROR: Asciidoctor / Ruby not found. Ensure prerequisites are installed."
            )
            return False
        except subprocess.CalledProcessError as e:
            log_func(
                f"ERROR: Asciidoctor failed for '{file_name_no_ext}'.\n  Details:\n{e.stderr}"
            )
            return False

    return True


# ---------------------------------------------------------------------------
# Tkinter GUI
# ---------------------------------------------------------------------------

class ConverterApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("S1000D Conversion Utility — Markdown")
        self.geometry("900x750")
        self.configure(bg="#E6E6FA")

        self.input_dir  = tk.StringVar()
        self.output_dir = tk.StringVar()
        self.dm_type    = tk.StringVar(value=S1000D_DM_TYPES[0])

        self.is_step1_running = False
        self.is_step2_running = False
        self.loader_chars     = ["|", "/", "—", "\\"]
        self.loader_index     = 0

        # Fonts
        self.heading_font    = font.Font(family="Helvetica", size=14, weight="bold")
        self.button_font     = font.Font(family="Helvetica", size=10, weight="bold")
        self.label_font      = font.Font(family="Helvetica", size=10)
        self.small_font      = font.Font(family="Helvetica", size=9, slant="italic")
        self.status_font     = font.Font(family="Helvetica", size=11)
        self.status_font_bold = font.Font(family="Helvetica", size=11, weight="bold")
        self.log_font        = font.Font(family="Consolas", size=10)

        # Colors
        self.bg_color            = "#E6E6FA"
        self.frame_bg            = "#FFFFFF"
        self.button_color        = "#4682B4"
        self.button_active_color = "#5F9EA0"
        self.text_color          = "#333333"

        self.status_pending_fg    = "gray"
        self.status_processing_fg = "#FF8C00"
        self.status_done_fg       = "#228B22"
        self.status_failed_fg     = "#B22222"

        # TTK style
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("TFrame",       background=self.bg_color)
        style.configure("White.TFrame", background=self.frame_bg,
                        relief="flat", borderwidth=1, bordercolor="#DDDDDD")
        style.configure("TLabel",       background=self.bg_color,
                        foreground=self.text_color, font=self.label_font)
        style.configure("White.TLabel", background=self.frame_bg,
                        foreground=self.text_color, font=self.label_font)
        style.configure("TButton",      font=self.button_font,
                        background=self.button_color, foreground="white",
                        padding=6, relief="flat")
        style.map("TButton",
                  background=[("active", self.button_active_color)],
                  foreground=[("active", "white")])
        style.configure("Accent.TButton", font=self.heading_font,
                        background="#4CAF50", foreground="white",
                        padding=10, relief="flat")
        style.map("Accent.TButton", background=[("active", "#66BB6A")])
        style.configure("TEntry", fieldbackground="white",
                        foreground=self.text_color, borderwidth=1, relief="solid")
        style.configure("TMenubutton", background=self.frame_bg,
                        foreground=self.text_color, font=self.label_font, padding=4)
        style.map("TMenubutton", background=[("active", self.button_active_color)])

        # --- Main frame ---
        main_frame = ttk.Frame(self, padding="15 15 15 15", style="TFrame")
        main_frame.pack(fill=tk.BOTH, expand=True)

        # --- Folder / type selection frame ---
        folder_frame = ttk.Frame(main_frame, padding="10 10", style="White.TFrame")
        folder_frame.pack(fill=tk.X, pady=(0, 15))
        folder_frame.columnconfigure(1, weight=1)

        # Input folder
        ttk.Label(folder_frame, text="Input Folder (.md):",
                  style="White.TLabel").grid(row=0, column=0, padx=(0, 15),
                                             pady=5, sticky="w")
        ttk.Button(folder_frame, text="Browse",
                   command=self.select_input_folder).grid(
            row=0, column=2, padx=(5, 0), sticky="ew")
        ttk.Label(folder_frame, textvariable=self.input_dir,
                  relief="solid", anchor="w", background="white",
                  borderwidth=1, padding=(5, 5)).grid(
            row=0, column=1, sticky="ew", ipady=2)

        # Output folder
        ttk.Label(folder_frame, text="Output Folder:",
                  style="White.TLabel").grid(row=1, column=0, padx=(0, 15),
                                             pady=5, sticky="w")
        ttk.Button(folder_frame, text="Browse",
                   command=self.select_output_folder).grid(
            row=1, column=2, padx=(5, 0), sticky="ew")
        ttk.Label(folder_frame, textvariable=self.output_dir,
                  relief="solid", anchor="w", background="white",
                  borderwidth=1, padding=(5, 5)).grid(
            row=1, column=1, sticky="ew", ipady=2)

        # DM Type dropdown
        ttk.Label(folder_frame, text="Select DM Type:",
                  style="White.TLabel").grid(row=2, column=0, padx=(0, 15),
                                             pady=5, sticky="w")
        dm_type_menu = ttk.OptionMenu(
            folder_frame,
            self.dm_type,
            S1000D_DM_TYPES[0],
            *S1000D_DM_TYPES,
            command=self._on_dm_type_change,
            style="TMenubutton",
        )
        dm_type_menu.grid(row=2, column=1, sticky="ew", ipady=2, pady=5)
        dm_type_menu.config(width=28)

        # DM type description label
        self.dm_desc_var = tk.StringVar(
            value=DM_TYPE_DESCRIPTIONS.get(S1000D_DM_TYPES[0], "")
        )
        ttk.Label(folder_frame, textvariable=self.dm_desc_var,
                  background=self.frame_bg,
                  foreground="#666666",
                  font=self.small_font).grid(
            row=3, column=1, sticky="w", padx=2, pady=(0, 5))

        # --- Start button ---
        self.start_button = ttk.Button(
            main_frame,
            text="Start Full Conversion",
            command=self.start_conversion_thread,
            style="Accent.TButton",
        )
        self.start_button.pack(pady=15, fill=tk.X, ipady=5)

        # --- Progress frame ---
        status_frame = ttk.LabelFrame(
            main_frame, text="Progress", padding="10 10", style="White.TFrame"
        )
        status_frame.pack(fill=tk.X, pady=8)
        status_frame.columnconfigure(2, weight=1)

        self.step1_loader = ttk.Label(status_frame, text="",
                                      font=self.status_font_bold, width=2,
                                      background=self.frame_bg)
        self.step1_loader.grid(row=0, column=0, sticky="w", padx=5)
        ttk.Label(status_frame, text="Step 1: Markdown → AsciiDoc",
                  font=self.status_font,
                  background=self.frame_bg).grid(row=0, column=1, sticky="w", pady=2)
        self.step1_status = ttk.Label(status_frame, text="Pending",
                                      font=self.status_font,
                                      foreground=self.status_pending_fg,
                                      background=self.frame_bg)
        self.step1_status.grid(row=0, column=2, sticky="e", padx=5)

        self.step2_loader = ttk.Label(status_frame, text="",
                                      font=self.status_font_bold, width=2,
                                      background=self.frame_bg)
        self.step2_loader.grid(row=1, column=0, sticky="w", padx=5)
        ttk.Label(status_frame, text="Step 2: AsciiDoc → S1000D XML",
                  font=self.status_font,
                  background=self.frame_bg).grid(row=1, column=1, sticky="w", pady=2)
        self.step2_status = ttk.Label(status_frame, text="Pending",
                                      font=self.status_font,
                                      foreground=self.status_pending_fg,
                                      background=self.frame_bg)
        self.step2_status.grid(row=1, column=2, sticky="e", padx=5)

        # --- Log ---
        ttk.Label(main_frame, text="Detailed Log:", anchor="w",
                  font=self.label_font, background=self.bg_color).pack(
            fill=tk.X, pady=(10, 5))
        self.log_widget = scrolledtext.ScrolledText(
            main_frame, wrap=tk.WORD, font=self.log_font,
            state=tk.DISABLED, bg="#f8f8f8", fg=self.text_color,
            relief="solid", borderwidth=1, padx=5, pady=5,
        )
        self.log_widget.pack(pady=5, fill=tk.BOTH, expand=True)

    # -----------------------------------------------------------------------
    # GUI helpers
    # -----------------------------------------------------------------------

    def _on_dm_type_change(self, value):
        self.dm_desc_var.set(DM_TYPE_DESCRIPTIONS.get(value, ""))

    def select_input_folder(self):
        path = filedialog.askdirectory(title="Select Folder Containing Markdown Files")
        if path:
            self.input_dir.set(path)

    def select_output_folder(self):
        path = filedialog.askdirectory(title="Select Base Output Folder")
        if path:
            self.output_dir.set(path)

    def log(self, message):
        self.after(0, self._update_log, message)

    def _update_log(self, message):
        self.log_widget.config(state=tk.NORMAL)
        self.log_widget.insert(tk.END, message + "\n")
        self.log_widget.config(state=tk.DISABLED)
        self.log_widget.see(tk.END)

    def update_status(self, label, text, color):
        self.after(0, lambda: label.config(text=text, foreground=color))

    def update_loader(self):
        if self.is_step1_running or self.is_step2_running:
            char = self.loader_chars[self.loader_index % len(self.loader_chars)]
            if self.is_step1_running:
                self.step1_loader.config(text=char)
            if self.is_step2_running:
                self.step2_loader.config(text=char)
            self.loader_index += 1
            self.after(100, self.update_loader)

    # -----------------------------------------------------------------------
    # Main conversion runner (called in a background thread)
    # -----------------------------------------------------------------------

    def run_full_conversion(self):
        self.start_button.config(state=tk.DISABLED)
        self.log_widget.config(state=tk.NORMAL)
        self.log_widget.delete("1.0", tk.END)
        self.log_widget.config(state=tk.DISABLED)

        self.update_status(self.step1_status, "Processing...", self.status_processing_fg)
        self.update_status(self.step2_status, "Pending", self.status_pending_fg)
        self.step1_loader.config(text="")
        self.step2_loader.config(text="")

        input_path       = self.input_dir.get()
        output_path      = self.output_dir.get()
        selected_dm_type = self.dm_type.get()

        if not all([input_path, output_path]):
            messagebox.showerror(
                "Error", "Please select both an Input and Output folder before starting."
            )
            self.start_button.config(state=tk.NORMAL)
            return

        final_dir = os.path.join(output_path, "S1000D_Output", "DMs")

        # Step 1
        self.is_step1_running = True
        adoc_contents = convert_step1(input_path, self.log, selected_dm_type)
        self.is_step1_running = False
        self.step1_loader.config(text="")

        if adoc_contents is None:
            self.update_status(self.step1_status, "✗ Failed", self.status_failed_fg)
            self.start_button.config(state=tk.NORMAL)
            self.log("\n❌ Process stopped — Step 1 failed.")
            return

        self.update_status(self.step1_status, "✓ Done", self.status_done_fg)

        # Step 2
        self.update_status(self.step2_status, "Processing...", self.status_processing_fg)
        self.is_step2_running = True
        step2_ok = convert_step2(adoc_contents, final_dir, self.log, selected_dm_type)
        self.is_step2_running = False
        self.step2_loader.config(text="")

        if not step2_ok:
            self.update_status(self.step2_status, "✗ Failed", self.status_failed_fg)
            self.log("\n❌ Process stopped — Step 2 failed.")
            self.start_button.config(state=tk.NORMAL)
            return

        self.update_status(self.step2_status, "✓ Done", self.status_done_fg)
        self.log("\n" + "-" * 70)
        self.log("✅ Full conversion completed successfully!")
        self.log(f"  Final S1000D XML files: '{final_dir}'")
        self.log("  No intermediate .adoc files were saved to disk.")
        self.start_button.config(state=tk.NORMAL)

    def start_conversion_thread(self):
        self.start_button.config(state=tk.DISABLED)
        self.is_step1_running = False
        self.is_step2_running = False
        self.after(100, self.update_loader)
        threading.Thread(target=self.run_full_conversion, daemon=True).start()


if __name__ == "__main__":
    app = ConverterApp()
    app.mainloop()
