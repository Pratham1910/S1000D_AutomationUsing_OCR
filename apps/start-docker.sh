#!/bin/bash

# Docker script to start frontend and backend projects

set -e

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    Starting Frontend and Backend     ${NC}"
echo -e "${BLUE}========================================${NC}"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Function: build and start frontend
start_frontend() {
    echo -e "\n${GREEN}[1/4] Building frontend Docker image...${NC}"
    cd "$SCRIPT_DIR/frontend"
    docker build -t glm-ocr-frontend:latest .

    echo -e "${GREEN}[2/4] Starting frontend container...${NC}"
    # Stop and remove existing container (if present)
    docker stop glm-ocr-frontend 2>/dev/null || true
    docker rm glm-ocr-frontend 2>/dev/null || true

    # Start new container
    docker run -d \
        --name glm-ocr-frontend \
        -p 3000:80 \
        --restart unless-stopped \
        glm-ocr-frontend:latest

    echo -e "${GREEN}✓ Frontend started at http://localhost:3000${NC}"
}

# Function: build and start backend
start_backend() {
    echo -e "\n${GREEN}[3/4] Building backend Docker image...${NC}"
    cd "$SCRIPT_DIR/backend"
    docker build -t glm-ocr-backend:latest .

    echo -e "${GREEN}[4/4] Starting backend container...${NC}"
    # Stop and remove existing container (if present)
    docker stop glm-ocr-backend 2>/dev/null || true
    docker rm glm-ocr-backend 2>/dev/null || true

    # Start new container
    docker run -d \
        --name glm-ocr-backend \
        -p 8000:8000 \
        --restart unless-stopped \
        glm-ocr-backend:latest

    echo -e "${GREEN}✓ Backend started at http://localhost:8000${NC}"
}

# Main flow
start_frontend
start_backend

echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}✓ All services started successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}Frontend:${NC} http://localhost:3000"
echo -e "${YELLOW}Backend:${NC}  http://localhost:8000"
echo -e "${YELLOW}API Docs:${NC} http://localhost:8000/docs"
echo -e "\n${YELLOW}View logs:${NC}"
echo -e "  Frontend: docker logs -f glm-ocr-frontend"
echo -e "  Backend:  docker logs -f glm-ocr-backend"
echo -e "\n${YELLOW}Stop services:${NC}"
echo -e "  docker stop glm-ocr-frontend glm-ocr-backend"
echo -e "${BLUE}========================================${NC}"
