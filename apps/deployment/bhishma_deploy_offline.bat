@echo off
setlocal enableextensions enabledelayedexpansion

set SCRIPT_DIR=%~dp0
set DIST_DIR=%SCRIPT_DIR%dist
set FRONTEND_IMAGE=bhishma-beta-frontend:latest
set BACKEND_IMAGE=bhishma-beta-backend:latest
set BUNDLE_TAR=%DIST_DIR%\bhishma-beta-images.tar
set FRONTEND_CONTAINER=bhishma-beta-frontend
set BACKEND_CONTAINER=bhishma-beta-backend
set NETWORK_NAME=bhishma-beta-net

echo ========================================
echo   Bhishma Beta - Offline Deploy
echo ========================================

where docker >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Docker is not installed or not in PATH.
  exit /b 1
)

if not exist "%BUNDLE_TAR%" (
  echo [ERROR] Bundle not found: %BUNDLE_TAR%
  echo Run bhishma_build_bundle.bat first.
  exit /b 1
)

echo [1/5] Loading Docker image bundle...
docker load -i "%BUNDLE_TAR%"
if errorlevel 1 (
  echo [ERROR] docker load failed.
  exit /b 1
)

echo [2/5] Creating network if needed...
docker network inspect %NETWORK_NAME% >nul 2>nul
if errorlevel 1 docker network create %NETWORK_NAME%

echo [3/5] Stopping old containers (if any)...
docker stop %FRONTEND_CONTAINER% >nul 2>nul
docker rm %FRONTEND_CONTAINER% >nul 2>nul
docker stop %BACKEND_CONTAINER% >nul 2>nul
docker rm %BACKEND_CONTAINER% >nul 2>nul

echo [4/5] Starting backend...
docker run -d ^
  --name %BACKEND_CONTAINER% ^
  --network %NETWORK_NAME% ^
  --restart unless-stopped ^
  --add-host host.docker.internal:host-gateway ^
  -e APP_NAME="Bhishma beta version" ^
  -e APP_VERSION="0.1.0-beta" ^
  -e LAYOUT_OCR_URL="http://host.docker.internal:5002/glmocr/parse" ^
  -p 8000:8000 ^
  %BACKEND_IMAGE%
if errorlevel 1 (
  echo [ERROR] Backend container failed to start.
  exit /b 1
)

echo [5/5] Starting frontend...
docker run -d ^
  --name %FRONTEND_CONTAINER% ^
  --network %NETWORK_NAME% ^
  --restart unless-stopped ^
  -p 3000:80 ^
  %FRONTEND_IMAGE%
if errorlevel 1 (
  echo [ERROR] Frontend container failed to start.
  exit /b 1
)

echo.
echo ========================================
echo Bhishma beta version is running.
echo Frontend: http://localhost:3000
echo Backend:  http://localhost:8000
echo API Docs: http://localhost:8000/docs
echo ========================================
echo.
echo Notes:
echo - This deployment is local/offline capable.
echo - OCR endpoint is configured to: http://host.docker.internal:5002/glmocr/parse
echo - Ensure your local OCR service is running on port 5002.

exit /b 0
