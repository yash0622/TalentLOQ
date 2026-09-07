# Production Multi-Arch Dockerfile for TalentLOQ FastAPI Backend
FROM python:3.10-slim

WORKDIR /app

# Prevent Python from writing .pyc files and enable unbuffered stdout/stderr logging
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Install system utilities and build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    build-essential \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Copy pinned requirements and install Python packages
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Ensure spaCy language model is pre-installed
RUN python -c "import spacy; spacy.load('en_core_web_sm')" || python -m spacy download en_core_web_sm

# Copy backend application source code
COPY . .

# Expose FastAPI backend port
EXPOSE 8000

# Health check via root endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8000/health || curl -f http://localhost:8000/ || exit 1

# Start FastAPI application with production Uvicorn settings
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
