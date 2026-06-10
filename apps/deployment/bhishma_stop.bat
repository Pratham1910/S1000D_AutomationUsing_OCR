@echo off
setlocal enableextensions

set FRONTEND_CONTAINER=bhishma-beta-frontend
set BACKEND_CONTAINER=bhishma-beta-backend

echo Stopping Bhishma beta containers...
docker stop %FRONTEND_CONTAINER% >nul 2>nul
docker rm %FRONTEND_CONTAINER% >nul 2>nul
docker stop %BACKEND_CONTAINER% >nul 2>nul
docker rm %BACKEND_CONTAINER% >nul 2>nul
echo Done.

exit /b 0
