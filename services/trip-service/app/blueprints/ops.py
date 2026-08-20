"""Operational endpoints: health, readiness, metrics, service registry."""
from flask import Blueprint, current_app, jsonify
from sqlalchemy import text

from app.extensions import db
from app.metrics import DB_UP, metrics_response

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
    """Readiness probe — verifies the database connection."""
    try:
        db.session.execute(text("SELECT 1"))
        DB_UP.set(1)
        return jsonify({"status": "ready"}), 200
    except Exception as exc:  # pragma: no cover - defensive
        DB_UP.set(0)
        current_app.logger.error("readiness check failed", extra={"error": str(exc)})
        return jsonify({"status": "not_ready", "error": "database_unavailable"}), 503


@bp.get("/metrics")
def metrics():
    return metrics_response()


@bp.get("/api/services")
def services():
    """Simple service registry — lists known services and their health."""
    ai_healthy = current_app.ai_planner_client.health()
    return (
        jsonify(
            {
                "services": [
                    {
                        "name": "trip-service",
                        "role": "backend-a",
                        "status": "healthy",
                        "self": True,
                    },
                    {
                        "name": "ai-planner-service",
                        "role": "backend-b",
                        "url": current_app.config["AI_PLANNER_URL"],
                        "status": "healthy" if ai_healthy else "unhealthy",
                    },
                ]
            }
        ),
        200,
    )


@bp.get("/api/services/<service_name>/health")
def service_health(service_name):
    if service_name == "trip-service":
        return jsonify({"name": "trip-service", "status": "healthy"}), 200
    if service_name == "ai-planner-service":
        ok = current_app.ai_planner_client.health()
        return (
            jsonify({"name": "ai-planner-service", "status": "healthy" if ok else "unhealthy"}),
            200 if ok else 503,
        )
    return jsonify({"error": "not_found", "message": "Unknown service"}), 404
