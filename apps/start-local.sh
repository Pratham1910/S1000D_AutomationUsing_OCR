#!/bin/bash

# Local script to start frontend and backend projects
# Uses Python for backend and pnpm for frontend

set -e

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}     Local Frontend + Backend Start   ${NC}"
echo -e "${BLUE}========================================${NC}"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Function: check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}✗ Error: $1 not found. Please install it first.${NC}"
        exit 1
    fi
}

# Check required commands
echo -e "\n${YELLOW}Checking dependencies...${NC}"
check_command python3
check_command pnpm

# Function: start backend
start_backend() {
    echo -e "\n${GREEN}[1/2] Starting backend...${NC}"
    cd "$SCRIPT_DIR/backend"

    # Check virtual environment
    if [ ! -d ".venv" ]; then
        echo -e "${YELLOW}Virtual environment not found. Creating...${NC}"
        python3 -m venv .venv
    fi

    # Activate virtual environment
    source .venv/bin/activate

    # Install dependencies if needed
    if [ ! -f ".venv/bin/uvicorn" ] || [ "pyproject.toml" -nt ".venv/bin/uvicorn" ]; then
        echo -e "${YELLOW}Installing backend dependencies...${NC}"
        pip install -e .
    fi

    # Start backend
    echo -e "${GREEN}Starting backend service...${NC}"
    uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload &
    BACKEND_PID=$!
    echo $BACKEND_PID > "$SCRIPT_DIR/.backend.pid"
    echo -e "${GREEN}✓ Backend started (PID: $BACKEND_PID)${NC}"
}

# Function: start frontend
start_frontend() {
    echo -e "\n${GREEN}[2/2] Starting frontend...${NC}"
    cd "$SCRIPT_DIR/frontend"

    # Install dependencies if needed
    if [ ! -d "node_modules" ]; then
        echo -e "${YELLOW}Installing frontend dependencies...${NC}"
        pnpm install
    fi

    # Start frontend
    echo -e "${GREEN}Starting frontend dev server...${NC}"
    pnpm dev --host 0.0.0.0 &
    FRONTEND_PID=$!
    echo $FRONTEND_PID > "$SCRIPT_DIR/.frontend.pid"
    echo -e "${GREEN}✓ Frontend started (PID: $FRONTEND_PID)${NC}"
}

# Main flow
start_backend
start_frontend

echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}✓ All services started successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}Frontend:${NC} http://localhost:5173"
echo -e "${YELLOW}Backend:${NC}  http://localhost:8000"
echo -e "${YELLOW}API Docs:${NC} http://localhost:8000/docs"
echo -e "\n${YELLOW}Process IDs saved to:${NC}"
echo -e "  Backend:  $SCRIPT_DIR/.backend.pid"
echo -e "  Frontend: $SCRIPT_DIR/.frontend.pid"
echo -e "\n${YELLOW}Stop commands:${NC}"
echo -e "  kill \$(cat $SCRIPT_DIR/.backend.pid)"
echo -e "  kill \$(cat $SCRIPT_DIR/.frontend.pid)"
echo -e "  or use: pkill -f 'uvicorn|pnpm dev'"
echo -e "${BLUE}========================================${NC}"

# Wait for user interrupt
echo -e "\n${YELLOW}Press Ctrl+C to stop all services${NC}"
# Keep script running until Ctrl+C
trap "echo -e '\n${RED}Stopping all services...${NC}'; kill \$(cat $SCRIPT_DIR/.backend.pid) 2>/dev/null || true; kill \$(cat $SCRIPT_DIR/.frontend.pid) 2>/dev/null || true; rm -f $SCRIPT_DIR/.backend.pid $SCRIPT_DIR/.frontend.pid; echo -e '${GREEN}All services stopped${NC}'; exit 0" INT TERM

# Keep script running
wait
