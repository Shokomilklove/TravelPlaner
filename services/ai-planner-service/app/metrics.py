"""Prometheus metrics for the AI Planner service."""
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

# --- Standard HTTP metrics ---
REQUEST_COUNT = Counter(
    "http_requests_total", "Total HTTP requests", ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds", "HTTP request latency in seconds", ["method", "endpoint"]
)

# --- AI generation metrics ---
AI_GENERATION_REQUESTS = Counter(
    "ai_generation_requests_total",
    "LLM generation requests by provider and outcome",
    ["provider", "status"],
)
AI_GENERATION_DURATION = Histogram(
    "ai_generation_duration_seconds",
    "Time spent generating a plan (seconds)",
    ["provider"],
)
AI_PROVIDER_UP = Gauge(
    "ai_provider_up",
    "Whether an AI provider is configured (1=yes, 0=no)",
    multiprocess_mode="livemax",
)


def init_metrics(app):
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
    if os.environ.get("PROMETHEUS_MULTIPROC_DIR"):
        registry = CollectorRegistry()
        multiprocess.MultiProcessCollector(registry)
    else:
        registry = REGISTRY
    return Response(generate_latest(registry), mimetype=CONTENT_TYPE_LATEST)
