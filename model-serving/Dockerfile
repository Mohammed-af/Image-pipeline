# Multi-stage build for better security and smaller final image
FROM python:3.12-slim as builder

RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY pyproject.toml uv.lock ./
RUN pip install --no-cache-dir uv \
    && /opt/venv/bin/pip install --no-cache-dir fastapi[standard] uvicorn open-clip-torch opencv-python pillow scikit-learn torch torchvision tqdm transformers tritonclient[grpc]

# Production stage
FROM python:3.12-slim as production

RUN groupadd -r appuser && useradd -r -g appuser -m -d /home/appuser appuser

RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libgcc-s1 \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get autoremove -y

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY --chown=appuser:appuser . .

RUN pip install --no-cache-dir \
    torch>=2.8.0+cpu \
    torchvision>=0.23.0+cpu \
    --index-url https://download.pytorch.org/whl/cpu

RUN mkdir -p /app/cache_token /home/appuser/.cache /home/appuser/.cache/uv \
    && chown -R appuser:appuser /app/cache_token /home/appuser/.cache \
    && chmod -R 755 /home/appuser/.cache \
    && chown -R appuser:appuser /home/appuser \
    && chown -R appuser:appuser /app

ENV CACHE_DIR=/app/cache_token
ENV TRITON_SERVER_URL=localhost:8001
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV UV_CACHE_DIR=/home/appuser/.cache/uv
ENV HOME=/home/appuser

USER appuser

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8003/health || exit 1

EXPOSE 8003

# Simple uvicorn command that works
CMD ["/opt/venv/bin/uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8003"]