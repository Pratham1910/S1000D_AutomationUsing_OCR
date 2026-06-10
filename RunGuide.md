Run it in local mode with 3 terminals.

Terminal A: start OCR service
From repo root:
python -m glmocr.server
Wait until you see:
Running on http://127.0.0.1:5002

Terminal B: start backend
From repo root:
Set-Location apps/backend
..venv\Scripts\python -m pip install -e .
$env:LAYOUT_OCR_URL="http://127.0.0.1:5002/glmocr/parse"
..venv\Scripts\python -m uvicorn app.main:app --host 0.0.0.0 --port 8000

Terminal C: start frontend
From repo root:
Set-Location apps/frontend
pnpm install
pnpm dev --host 0.0.0.0 --port 3006

Open:

http://localhost:3006
Backend health: http://localhost:8000/health
OCR health: http://localhost:5002/health
If backend exits with code 1:

Port 8000 is usually already in use.
Run:
$pid = (Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty OwningProcess)
if ($pid) { Stop-Process -Id $pid -Force }
Start backend again.
If you prefer script-based starts, Linux-style helpers are already in start-local.sh and start-docker.sh. For Windows, I can create a single local start .bat that launches all 3 services