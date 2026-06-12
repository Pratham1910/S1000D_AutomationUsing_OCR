#!/usr/bin/env python3
"""
S1000D Converter Suite – Web UI server
=======================================
Wraps the converter pipeline behind a lightweight Flask API so it can be
driven from the Tailwind HTML frontend instead of tkinter.

Usage
-----
    pip install flask
    python server.py          # opens http://127.0.0.1:7860
"""

import sys, json, threading, queue, time, traceback, uuid
from pathlib import Path
try:
    import urllib.request as _urllib_req
except ImportError:
    _urllib_req = None

# ── Import the converter (tkinter is imported at the top of the suite but
#    never instantiated here, so it is safe on any platform). ─────────────────
_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))

from S1000D_Converter_Suite import (
    build_package,
    S1000D_DM_TYPES,
    DM_TYPE_DESC,
)
import S1000D_Converter_Suite as _suite

from flask import Flask, render_template, request, jsonify, Response, stream_with_context

app = Flask(__name__, template_folder="templates")

# ── Job registry ──────────────────────────────────────────────────────────────

class _Job:
    """State container for a single conversion run."""

    def __init__(self):
        self.q    = queue.Queue()
        self.stop = threading.Event()

    # ── producers (called from worker thread) ────────────────────────────────

    def _put(self, d: dict) -> None:
        self.q.put(json.dumps(d))

    def log(self, msg: str, tag: str = "") -> None:
        if not tag:
            m = msg.strip()
            if m.startswith("─") or m.startswith("═"):
                tag = "sep"
            elif "error" in m.lower() or "failed" in m.lower() or "exception" in m.lower():
                tag = "err"
            elif "warning" in m.lower() or "warn" in m.lower() or "fallback" in m.lower():
                tag = "warn"
            elif any(k in m.lower() for k in ("ok", "done", "finished", "saved", "written")):
                tag = "ok"
            elif m.startswith("  →") or m.startswith("→"):
                tag = "arrow"
            elif any(k in m for k in ("Output", "Files to process", "Extracting")):
                tag = "file"
            elif "[1/4]" in m or "[2/4]" in m or "[3/4]" in m or "[4/4]" in m:
                tag = "step"
        self._put({"type": "log", "msg": msg, "tag": tag})

    def progress(self, pct: float, step: str, file_idx: int, total: int) -> None:
        self._put({"type": "progress", "pct": round(min(100, max(0, pct)), 1),
                   "step": step, "file_idx": file_idx, "total": total})

    def done(self, ok: int, fail: int, elapsed: float) -> None:
        self._put({"type": "done", "ok": ok, "fail": fail,
                   "elapsed": round(elapsed, 1)})


_jobs: dict[str, _Job] = {}


# ── Routes ────────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    return render_template(
        "index.html",
        dm_types=S1000D_DM_TYPES,
        dm_descs=DM_TYPE_DESC,
        defaults={
            "ollama_model":       getattr(_suite, "OLLAMA_MODEL",           "llama3.1:8b"),
            "glmocr_backend":     getattr(_suite, "GLMOCR_BACKEND",         "default"),
            "glmocr_ollama_url":  getattr(_suite, "GLMOCR_OLLAMA_URL",      "http://127.0.0.1:11434/api/generate"),
            "glmocr_ollama_model":getattr(_suite, "GLMOCR_OLLAMA_MODEL",    "glm-ocr:latest"),
            "odl_hybrid_url":     getattr(_suite, "ODL_HYBRID_URL",         "http://127.0.0.1:5002"),
            "odl_use_hybrid":     getattr(_suite, "ODL_USE_HYBRID",         False),
        },
    )


@app.route("/api/jobs", methods=["POST"])
def create_job():
    data = request.get_json(force=True) or {}

    files = [Path(p.strip()) for p in data.get("files", []) if p.strip()]
    if not files:
        return jsonify({"error": "No file paths provided."}), 400

    missing = [str(p) for p in files if not p.exists()]
    if missing:
        return jsonify({"error": f"Not found: {', '.join(missing)}"}), 400

    out_root  = Path(data.get("output_dir", "").strip() or str(_HERE / "S1000D_Output"))
    dm_type   = data.get("dm_type",   "auto")
    force_ocr = bool(data.get("force_ocr", False))

    # Sync module-level globals from request payload
    _suite.USE_OLLAMA_TEMPLATE   = bool(data.get("use_ollama_template",  True))
    _suite.OLLAMA_MODEL          = data.get("ollama_model",  _suite.OLLAMA_MODEL)  or _suite.OLLAMA_MODEL
    _suite.GLMOCR_BACKEND        = data.get("glmocr_backend", _suite.GLMOCR_BACKEND) or "default"
    _suite.GLMOCR_OLLAMA_URL     = data.get("glmocr_ollama_url",   _suite.GLMOCR_OLLAMA_URL)   or _suite.GLMOCR_OLLAMA_URL
    _suite.GLMOCR_OLLAMA_MODEL   = data.get("glmocr_ollama_model", _suite.GLMOCR_OLLAMA_MODEL) or _suite.GLMOCR_OLLAMA_MODEL
    _suite.ODL_USE_HYBRID        = bool(data.get("odl_use_hybrid", False))
    _suite.ODL_HYBRID_URL        = data.get("odl_hybrid_url", _suite.ODL_HYBRID_URL) or _suite.ODL_HYBRID_URL

    out_formats = {
        "raw_json":    bool(data.get("out_raw_json",    True)),
        "sem_json":    bool(data.get("out_sem_json",    True)),
        "xml":         bool(data.get("out_xml",         True)),
        "adoc":        bool(data.get("out_adoc",        True)),
        "md":          bool(data.get("out_md",          True)),
        "assets":      bool(data.get("out_assets",      True)),
        "glm_default": bool(data.get("out_glm_default", True)),
    }

    job_id       = str(uuid.uuid4())[:8]
    job          = _Job()
    _jobs[job_id] = job
    total        = len(files)

    def _worker():
        t0   = time.perf_counter()
        ok   = fail = 0
        out_pkg = out_root / "S1000D_Package"
        out_pkg.mkdir(parents=True, exist_ok=True)

        job.log(f"Output  : {out_pkg.resolve()}", "file")
        job.log(f"Files   : {total}",             "file")
        job.log("─" * 48, "sep")

        for idx, src in enumerate(files):
            if job.stop.is_set():
                job.log("⏹  Stopped by user.", "warn")
                break

            job.progress(idx / total * 100, "Starting…", idx, total)
            job.log(f"[{idx+1}/{total}]  {src.name}", "file")

            def _prog(step, nsteps, step_name, _i=idx, _t=total):
                pct = (_i / _t + step / (nsteps * _t)) * 100
                job.progress(pct, step_name, _i, _t)

            try:
                success = build_package(
                    src_path    = src,
                    out_root    = out_pkg,
                    dm_type     = dm_type,
                    force_ocr   = force_ocr,
                    out_formats = out_formats,
                    log         = job.log,
                    stop_event  = job.stop,
                    progress_cb = _prog,
                )
                if success:
                    ok   += 1
                    job.log(f"  ✓  {src.name}", "ok")
                else:
                    fail += 1
                    job.log(f"  ⚠  {src.name} — skipped", "warn")
            except Exception as exc:
                fail += 1
                job.log(f"  ✗  {src.name} — {exc}", "err")
                traceback.print_exc()

        elapsed = time.perf_counter() - t0
        job.log("─" * 48, "sep")
        job.done(ok, fail, elapsed)

    threading.Thread(target=_worker, daemon=True).start()
    return jsonify({"job_id": job_id})


@app.route("/api/jobs/<job_id>/events")
def job_events(job_id: str):
    job = _jobs.get(job_id)
    if not job:
        return jsonify({"error": "unknown job"}), 404

    def _stream():
        while True:
            try:
                msg = job.q.get(timeout=25)
                yield f"data: {msg}\n\n"
                if json.loads(msg).get("type") == "done":
                    break
            except queue.Empty:
                yield 'data: {"type":"ping"}\n\n'

    return Response(
        stream_with_context(_stream()),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.route("/api/jobs/<job_id>/stop", methods=["POST"])
def stop_job(job_id: str):
    job = _jobs.get(job_id)
    if job:
        job.stop.set()
        return jsonify({"ok": True})
    return jsonify({"error": "unknown job"}), 404


# ── Settings API ──────────────────────────────────────────────────────────────

_SETTINGS_KEYS = {
    "ollama_url":         ("OLLAMA_URL",           "http://127.0.0.1:11434/api/generate"),
    "ollama_model":       ("OLLAMA_MODEL",          "llama3.1:8b"),
    "use_ollama_template":("USE_OLLAMA_TEMPLATE",   True),
    "glmocr_backend":     ("GLMOCR_BACKEND",        "default"),
    "glmocr_ollama_url":  ("GLMOCR_OLLAMA_URL",     "http://127.0.0.1:11434/api/generate"),
    "glmocr_ollama_model":("GLMOCR_OLLAMA_MODEL",   "glm-ocr:latest"),
    "odl_use_hybrid":     ("ODL_USE_HYBRID",        False),
    "odl_hybrid_url":     ("ODL_HYBRID_URL",        "http://127.0.0.1:5002"),
    "ocr_workers":        ("OCR_WORKERS",           4),
}


@app.route("/api/settings", methods=["GET"])
def get_settings():
    out = {}
    for key, (attr, default) in _SETTINGS_KEYS.items():
        out[key] = getattr(_suite, attr, default)
    return jsonify(out)


@app.route("/api/settings", methods=["POST"])
def save_settings():
    data = request.get_json(force=True) or {}
    for key, (attr, default) in _SETTINGS_KEYS.items():
        if key in data:
            val = data[key]
            # Coerce types
            if isinstance(default, bool):
                val = bool(val)
            elif isinstance(default, int):
                try:
                    val = max(1, int(val))
                except (TypeError, ValueError):
                    val = default
            elif isinstance(default, str):
                val = str(val).strip() or default
            setattr(_suite, attr, val)
    return jsonify({"ok": True})


@app.route("/api/test-ollama")
def test_ollama():
    """Ping an Ollama server — returns {ok, latency_ms, error?}."""
    raw_url = request.args.get("url", "").strip()
    if not raw_url:
        return jsonify({"ok": False, "error": "url param required"}), 400

    # Normalise: strip /api/generate suffix so we hit the tags endpoint
    base = raw_url.rstrip("/")
    for suffix in ("/api/generate", "/api/chat"):
        if base.endswith(suffix):
            base = base[: -len(suffix)]
            break
    ping_url = base.rstrip("/") + "/api/tags"

    t0 = time.perf_counter()
    try:
        req = _urllib_req.Request(ping_url, headers={"Accept": "application/json"})
        with _urllib_req.urlopen(req, timeout=5) as resp:
            body  = json.loads(resp.read().decode())
            ms    = round((time.perf_counter() - t0) * 1000)
            models = [m.get("name", "") for m in body.get("models", [])]
            return jsonify({"ok": True, "latency_ms": ms, "models": models})
    except Exception as exc:
        return jsonify({"ok": False, "error": str(exc),
                        "latency_ms": round((time.perf_counter() - t0) * 1000)})


@app.route("/api/list-models")
def list_models():
    """Return model names available on an Ollama instance."""
    raw_url = request.args.get("url", "").strip()
    if not raw_url:
        return jsonify({"models": []}), 400
    base = raw_url.rstrip("/")
    for suffix in ("/api/generate", "/api/chat"):
        if base.endswith(suffix):
            base = base[: -len(suffix)]
            break
    tags_url = base.rstrip("/") + "/api/tags"
    try:
        req = _urllib_req.Request(tags_url, headers={"Accept": "application/json"})
        with _urllib_req.urlopen(req, timeout=5) as resp:
            body   = json.loads(resp.read().decode())
            models = [m.get("name", "") for m in body.get("models", [])]
            return jsonify({"models": models})
    except Exception as exc:
        return jsonify({"models": [], "error": str(exc)})


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("\n  S1000D Converter Suite — Web UI")
    print("  ─────────────────────────────────")
    print("  Open → http://127.0.0.1:7860\n")
    app.run(host="127.0.0.1", port=7860, debug=False, threaded=True)
