# Use official Python 3.12 image as base image
FROM python:3.12-slim

# Set working directory
WORKDIR /app

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DISPLAY=:99 \
    HOME=/tmp

# Install system dependencies
# - poppler-utils: PDF processing dependency (pdf2image)
# - libgomp1: OpenMP support (required by some CV libs)
# - libglib2.0-0: GLib support
# - libsm6: X11 library support
# - libxext6: X11 extension library
# - libxrender-dev: X11 rendering library
# - libgl1: OpenGL support
# - libreoffice*: LibreOffice suite (Word-to-PDF conversion)
# - fonts-*: Font support (including CJK)
RUN apt-get update && apt-get install -y --no-install-recommends \
    poppler-utils \
    libgomp1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1 \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-impress \
    libreoffice-core \
    fonts-dejavu \
    fonts-liberation \
    fonts-noto-cjk \
    fonts-wqy-zenhei \
    && rm -rf /var/lib/apt/lists/* \
    && libreoffice --version \
    && libreoffice --headless --version

# Copy project files
COPY pyproject.toml ./
COPY app ./app

# Create an empty README.md (referenced by pyproject.toml)
RUN touch README.md

# Install project dependencies
RUN pip install --no-cache-dir -e .


# Expose port (default: 8000)
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8000/health')" || exit 1

# Run app
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]