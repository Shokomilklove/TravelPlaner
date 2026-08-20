# syntax=docker/dockerfile:1

# ---------- Builder ----------
FROM python:3.12-slim AS builder
ENV PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY requirements.txt .
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install -r requirements.txt

# ---------- Runtime ----------
FROM python:3.12-slim AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    APP_ENV=production \
    PORT=5002 \
    PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus_multiproc

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && addgroup --system app \
    && adduser --system --ingroup app app

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY . .

RUN sed -i 's/\r$//' entrypoint.sh \
    && chmod +x entrypoint.sh \
    && mkdir -p "$PROMETHEUS_MULTIPROC_DIR" \
    && chown -R app:app /app "$PROMETHEUS_MULTIPROC_DIR"

USER app
EXPOSE 5002
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fsS http://localhost:5002/health || exit 1

ENTRYPOINT ["./entrypoint.sh"]
CMD ["gunicorn", "-c", "gunicorn.conf.py", "wsgi:app"]
