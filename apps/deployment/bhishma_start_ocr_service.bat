@echo off
setlocal enableextensions

set SCRIPT_DIR=%~dp0
for %%I in ("%SCRIPT_DIR%..\..") do set REPO_ROOT=%%~fI

echo ========================================
echo   Bhishma Beta - Start OCR Service
echo ========================================

where python >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Python is not installed or not in PATH.
  exit /b 1
)

cd /d "%REPO_ROOT%"
echo Starting local OCR service at http://127.0.0.1:5002 ...
echo Keep this window open while Bhishma backend is running.
echo.
python -m glmocr.server

exit /b %errorlevel%
