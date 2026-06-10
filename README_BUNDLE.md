Bundling S1000D Converter Suite for Windows

This repository includes a helper script to produce a portable executable using PyInstaller.

Quick steps (Windows PowerShell):

1. Create a clean virtualenv and install build deps (script does this for you):

```powershell
# From repository root
.\scripts\build_exe.ps1 -OneFile -Clean
```

2. The resulting exe will be in `dist\S1000D_Converter_Suite.exe` (one-file) or `dist\S1000D_Converter_Suite` folder.

Notes & caveats:

- The application bundles Python and the runtime libraries, but not large ML model weights. If you use the Ollama backend (`glm-ocr:latest`) you must have Ollama and the model present on each target machine.
- The layout detector (PP-DocLayoutV3) may download from Hugging Face on first run unless you pre-populate a local snapshot and set the environment variable `S1000D_GLMOCR_LAYOUT_MODEL_DIR` to that path.
- If the target machine does not have a GPU or the optional layout/self-hosted extras, prefer using Ollama (local) or a MaaS provider.

Environment variables useful on target:

- `S1000D_GLMOCR_BACKEND=ollama` (use Ollama)
- `S1000D_GLMOCR_OLLAMA_URL=http://127.0.0.1:11434/api/generate`
- `S1000D_GLMOCR_OLLAMA_MODEL=glm-ocr:latest`
- `S1000D_GLMOCR_LAYOUT_MODEL_DIR=C:\path\to\local\ppdoclayout\snapshot`

If you want, I can:

- Run the build script locally (will be large and may take time).
- Add a GUI field to configure `layout model dir` so the packaged EXE can be configured without env vars.
