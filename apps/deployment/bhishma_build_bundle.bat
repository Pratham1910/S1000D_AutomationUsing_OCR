@echo off
setlocal enableextensions enabledelayedexpansion

set SCRIPT_DIR=%~dp0
for %%I in ("%SCRIPT_DIR%..\..") do set REPO_ROOT=%%~fI
set DIST_DIR=%SCRIPT_DIR%dist
set FRONTEND_IMAGE=bhishma-beta-frontend:latest
set BACKEND_IMAGE=bhishma-beta-backend:latest
set BUNDLE_TAR=%DIST_DIR%\bhishma-beta-images.tar

echo ========================================
echo   Bhishma Beta - Build Offline Bundle
echo ========================================

where docker >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Docker is not installed or not in PATH.
  exit /b 1
)

if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

pushd "%REPO_ROOT%"
echo [1/4] Building backend image: %BACKEND_IMAGE%
docker build -t %BACKEND_IMAGE% apps\backend
if errorlevel 1 (
  echo [ERROR] Backend image build failed.
  popd
  exit /b 1
)

echo [2/4] Building frontend image: %FRONTEND_IMAGE%
docker build -t %FRONTEND_IMAGE% apps\frontend
if errorlevel 1 (
  echo [ERROR] Frontend image build failed.
  popd
  exit /b 1
)

echo [3/4] Saving Docker images to TAR: %BUNDLE_TAR%
docker save -o "%BUNDLE_TAR%" %BACKEND_IMAGE% %FRONTEND_IMAGE%
if errorlevel 1 (
  echo [ERROR] Failed to create image tar.
  popd
  exit /b 1
)

echo [4/4] Build bundle completed.
echo.
echo Bundle created:
echo   %BUNDLE_TAR%
echo.
echo Next step on offline machine:
echo   Run deployment\bhishma_deploy_offline.bat

popd
exit /b 0
