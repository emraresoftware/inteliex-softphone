# Dockerfile for emrecode (FastAPI + async SQLAlchemy)
# Build stage
FROM python:3.12-slim-bookworm AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY emrecode/requirements.txt .
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt

# Runtime stage
FROM python:3.12-slim-bookworm

WORKDIR /app

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy Python packages from builder
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application code
COPY emrecode/ /app/

# Create non-root user first (before chown)
RUN useradd -m -u 1000 emrecode

# Create data and workspace directories with proper permissions
RUN mkdir -p /data /workspace && \
    chown -R emrecode:emrecode /app /data /workspace && \
    chmod 755 /data /workspace

USER emrecode

# Expose port (default 9870, can be overridden)
EXPOSE 9870

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:9870/api/health || exit 1

# Default environment
ENV LISTEN_HOST=0.0.0.0 \
    LISTEN_PORT=9870 \
    DEV_MODE=false \
    DB_URL=sqlite+aiosqlite:///./emrecode.db \
    HUB_URL=http://127.0.0.1:9860

# Run FastAPI server via uvicorn
CMD ["python", "-m", "uvicorn", "app.server:app", "--host", "0.0.0.0", "--port", "9870"]
