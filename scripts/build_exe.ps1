# Build script for creating a Windows executable using PyInstaller
# Usage (PowerShell):
#   .\scripts\build_exe.ps1 -OneFile -Clean

param(
    [switch]$OneFile = $true,
    [switch]$Clean = $true,
    [string]$Entry = "S1000D_Converter_Suite.py",
    [string]$DistName = "S1000D_Converter_Suite",
    [string]$VenvDir = ".venv_build",
    [switch]$PortableBundle = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LocalLayoutSnapshot {
    $cacheRoot = Join-Path $env:USERPROFILE ".cache\huggingface\hub"
    $snapshots = Join-Path $cacheRoot "models--PaddlePaddle--PP-DocLayoutV3_safetensors\snapshots"
    if (Test-Path $snapshots) {
        $best = Get-ChildItem $snapshots -Directory | Where-Object {
            (Test-Path (Join-Path $_.FullName "preprocessor_config.json")) -and (Test-Path (Join-Path $_.FullName "config.json"))
        } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($best) { return $best.FullName }
    }

    $root = Join-Path $cacheRoot "models--PaddlePaddle--PP-DocLayoutV3_safetensors"
    if ((Test-Path (Join-Path $root "preprocessor_config.json")) -and (Test-Path (Join-Path $root "config.json"))) {
        return $root
    }

    return $null
}

Write-Host "Creating build virtualenv at: $VenvDir"
if (Test-Path $VenvDir -PathType Container) {
    if ($Clean) { Remove-Item $VenvDir -Recurse -Force }
}
python -m venv $VenvDir
$pip = Join-Path $VenvDir "Scripts\pip.exe"
$python = Join-Path $VenvDir "Scripts\python.exe"

Write-Host "Installing PyInstaller and runtime requirements..."
& $python -m pip install --upgrade pip
& $python -m pip install pyinstaller
& $python -m pip install -r requirements.txt
& $python -m pip install .
Write-Host "OpenCV is included so the GLM-OCR layout detector can import cv2 in the packaged EXE."

# Ensure glmocr package importable (local package)
Write-Host "Running PyInstaller..."
$pyinstallerArgs = @(
    "--name", $DistName,
    "--noconfirm",
    "--hidden-import=tkinter",
    "--hidden-import=glmocr",
    "--add-data", "Templates;Templates",
    "--add-data", "resources;resources"
)
if ($OneFile) { $pyinstallerArgs += "--onefile" }

# If you need console visible, omit --noconsole
$pyinstallerArgs += "--console"
$pyinstallerArgs += $Entry

& $python -m PyInstaller @pyinstallerArgs

Write-Host "Build complete. See dist\$DistName (or dist\$DistName.exe for onefile)."

if ($PortableBundle) {
    $snapshot = Get-LocalLayoutSnapshot
    $portableRoot = Join-Path (Get-Location) "dist\Portable\$DistName"
    if (Test-Path $portableRoot) { Remove-Item $portableRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $portableRoot | Out-Null

    $exeSource = Join-Path (Get-Location) "dist\$DistName.exe"
    if (-not (Test-Path $exeSource)) {
        $exeSource = Join-Path (Get-Location) "dist\$DistName\$DistName.exe"
    }
    Copy-Item $exeSource (Join-Path $portableRoot "$DistName.exe") -Force

    if ($snapshot) {
        $layoutTarget = Join-Path $portableRoot "layout_models\PP-DocLayoutV3_safetensors"
        New-Item -ItemType Directory -Path $layoutTarget -Force | Out-Null
        Copy-Item (Join-Path $snapshot "*") $layoutTarget -Recurse -Force
        $launcher = @"
@echo off
setlocal
set "S1000D_GLMOCR_BACKEND=ollama"
set "S1000D_GLMOCR_OLLAMA_MODEL=glm-ocr:latest"
set "S1000D_GLMOCR_LAYOUT_MODEL_DIR=%~dp0layout_models\PP-DocLayoutV3_safetensors"
"%~dp0$DistName.exe"
"@
        Set-Content -Path (Join-Path $portableRoot "run_portable.bat") -Value $launcher -Encoding ASCII
        Write-Host "Portable bundle created at: $portableRoot"
        Write-Host "Launcher: $portableRoot\run_portable.bat"
    } else {
        Write-Host "Portable bundle requested, but no local PP-DocLayout snapshot was found."
    }
}

Write-Host "Notes:"
Write-Host " - The produced EXE may be large. If your pipeline uses GPU or large transformers models, keep those models external or pre-install on target machines."
Write-Host " - Ollama-based OCR requires Ollama to be installed and the model (glm-ocr:latest) available on target machine, or change backend to a cloud MaaS provider."
