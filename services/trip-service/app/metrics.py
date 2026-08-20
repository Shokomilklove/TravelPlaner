"""Prometheus metrics.

Exposes standard HTTP request metrics plus custom business metrics. Works both
in single-process mode (dev, ``flask run``) and multi-process mode under
gunicorn when ``PROMETHEUS_MULTIPROC_DIR`` is set.
"""
import os
import time

from flask import Response, g, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    REGISTRY,
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
    multiprocess,
)

# --- Standard HTTP metrics ------------------------------------------------
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
)

# --- Custom business metrics ---------------------------------------------
USERS_REGISTERED = Counter("users_registered_total", "Total users registered")
TRIPS_CREATED = Counter("trips_created_total", "Total trips created")
TRIPS_SAVED = Counter("trips_saved_total", "Total trips saved")
AI_PLAN_REQUESTS = Counter(
    "ai_plan_requests_total", "AI planning requests by outcome", ["status"]
)
AI_PLAN_DURATION = Histogram(
    "ai_plan_request_duration_seconds", "Time spent calling the AI Planner service"
)
AI_PLAN_FAILURES = Counter(
    "ai_plan_failures_total", "AI planning failures by reason", ["reason"]
)
DB_UP = Gauge(
    "trip_service_db_up",
    "Whether the database is reachable (1=up, 0=down)",
    multiprocess_mode="livemax",
)


def init_metrics(app):
    """Register request timing hooks on the app."""

    @app.before_request
    def _start_timer():
        g._metrics_start = time.perf_counter()

    @app.after_request
    def _record(response):
        endpoint = request.endpoint or "unknown"
        if endpoint != "ops.metrics":
            elapsed = time.perf_counter() - getattr(
                g, "_metrics_start", time.perf_counter()
            )
            REQUEST_LATENCY.labels(request.method, endpoint).observe(elapsed)
            REQUEST_COUNT.labels(request.method, endpoint, response.status_code).inc()
        return response


def metrics_response():
    """Render the Prometheus exposition format for the /metrics endpoint."""
    if os.environ.get("PROMETHEUS_MULTIPROC_DIR"):
        registry = CollectorRegistry()
        multiprocess.MultiProcessCollector(registry)
    else:
        registry = REGISTRY
    return Response(generate_latest(registry), mimetype=CONTENT_TYPE_LATEST)
