"""AI Planner Service (Backend B) application factory."""
import uuid

from flask import Flask, g, request

from app.config import get_config
from app.errors import register_error_handlers
from app.logging_config import configure_logging
from app.metrics import AI_PROVIDER_UP, init_metrics
from app.providers import ProviderError, build_provider


def create_app(config_object=None):
    app = Flask(__name__)
    app.config.from_object(config_object or get_config())

    configure_logging(app)

    # Build the configured LLM provider. If misconfigured the service still
    # starts (so health checks pass) but planning endpoints return 503.
    try:
        app.llm_provider = build_provider(app.config)
        AI_PROVIDER_UP.set(1)
        app.logger.info(
            "AI provider ready",
            extra={"provider": app.llm_provider.name, "model": app.llm_provider.model},
        )
    except ProviderError as exc:
        app.llm_provider = None
        AI_PROVIDER_UP.set(0)
        app.logger.warning("AI provider not configured", extra={"error": str(exc)})

    _register_request_id(app)
    init_metrics(app)
    register_error_handlers(app)
    _register_blueprints(app)

    return app


def _register_blueprints(app):
    from app.blueprints.ops import bp as ops_bp
    from app.blueprints.plan import bp as plan_bp

    app.register_blueprint(plan_bp)
    app.register_blueprint(ops_bp)


def _register_request_id(app):
    @app.before_request
    def _assign_request_id():
        g.request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())

    @app.after_request
    def _return_request_id(response):
        if getattr(g, "request_id", None):
            response.headers["X-Request-ID"] = g.request_id
        return response
