# syntax=docker/dockerfile:1.7
# Multi-stage build for the Agent 365 sample agent.
# Image is consumed by Azure Container Apps; the same image runs anywhere with
# Docker (AKS, App Service for Containers, local `docker run`, etc.).

# --- Builder ---------------------------------------------------------------
FROM python:3.11-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv

# Install `uv` (same tool used in local dev) to resolve the lockfile.
RUN pip install --no-cache-dir "uv>=0.5"

WORKDIR /app

# Copy only dependency files first so the layer cache survives source edits.
COPY pyproject.toml uv.lock* ./

# Install deps into /opt/venv. --frozen requires uv.lock to be in sync.
RUN uv sync --no-dev --frozen \
    || uv sync --no-dev          # fall back if no lockfile yet

# --- Runtime ---------------------------------------------------------------
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    HOST=0.0.0.0 \
    PORT=3978

WORKDIR /app

# Non-root user for Container Apps compliance.
RUN groupadd --system app && useradd --system --gid app --home /app app

# Bring the resolved environment over from the builder.
COPY --from=builder /opt/venv /opt/venv

# Copy the application source. Keep this last so source edits invalidate
# only the final layer.
COPY --chown=app:app . .

USER app

EXPOSE 3978

# Container Apps probes /api/health on the listening port.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request,sys; \
sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:'+__import__('os').environ.get('PORT','3978')+'/api/health', timeout=3).status==200 else 1)" \
    || exit 1

# Entrypoint binds 0.0.0.0:$PORT and serves /api/messages + /api/health.
CMD ["python", "host_agent_server.py"]
