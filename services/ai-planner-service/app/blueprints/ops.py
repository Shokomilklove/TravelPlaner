"""Operational endpoints: health, readiness, metrics."""
from flask import Blueprint, current_app, jsonify

from app.metrics import AI_PROVIDER_UP, metrics_response

bp = Blueprint("ops", __name__)


@bp.get("/health")
def health():
    """Liveness probe — always 200 if the process is up."""
    return (
        jsonify(
            {
                "status": "ok",
                "service": current_app.config["SERVICE_NAME"],
                "version": current_app.config["SERVICE_VERSION"],
            }
        ),
        200,
    )


@bp.get("/ready")
def ready():
    """Readiness probe — verifies an AI provider is configured.

    Note: this confirms configuration, not live LLM reachability (pinging the
    LLM on every probe would be costly / rate-limited).
    """
    configured = current_app.llm_provider is not None
    AI_PROVIDER_UP.set(1 if configured else 0)
    if configured:
        return jsonify({"status": "ready", "provider": current_app.config["AI_PROVIDER"]}), 200
    return jsonify({"status": "not_ready", "error": "provider_unavailable"}), 503


@bp.get("/metrics")
def metrics():
    return metrics_response()
