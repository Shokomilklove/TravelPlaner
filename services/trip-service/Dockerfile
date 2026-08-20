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
    FLASK_APP=wsgi.py \
    APP_ENV=production \
    PORT=5001 \
    PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus_multiproc

# curl for the container HEALTHCHECK; create an unprivileged user.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && addgroup --system app \
    && adduser --system --ingroup app app

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY . .

# Normalise line endings on the entrypoint (repo may be checked out on Windows),
# make it executable, and hand ownership to the non-root user.
RUN sed -i 's/\r$//' entrypoint.sh \
    && chmod +x entrypoint.sh \
    && mkdir -p "$PROMETHEUS_MULTIPROC_DIR" \
    && chown -R app:app /app "$PROMETHEUS_MULTIPROC_DIR"

USER app
EXPOSE 5001
HEALTHCHECK --interval=30s --timeout=5s --start-period=25s --retries=3 \
    CMD curl -fsS http://localhost:5001/health || exit 1

ENTRYPOINT ["./entrypoint.sh"]
CMD ["gunicorn", "-c", "gunicorn.conf.py", "wsgi:app"]
