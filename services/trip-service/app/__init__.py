"""Trip Service (Backend A) application factory."""
import uuid

from flask import Flask, g, request

from app.clients.ai_planner import AIPlannerClient
from app.config import get_config
from app.errors import register_error_handlers
from app.extensions import cors, db, jwt, migrate
from app.logging_config import configure_logging
from app.metrics import init_metrics


def create_app(config_object=None):
    app = Flask(__name__)
    app.config.from_object(config_object or get_config())

    configure_logging(app)

    db.init_app(app)
    migrate.init_app(app, db)
    jwt.init_app(app)
    cors.init_app(
        app,
        resources={
            r"/api/*": {
                "origins": _cors_origins(app),
                "allow_headers": ["Authorization", "Content-Type", "X-Request-ID"],
                "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
            }
        },
    )

    # Ensure models are imported so metadata is populated for migrations.
    from app import models  # noqa: F401

    app.ai_planner_client = AIPlannerClient(
        base_url=app.config["AI_PLANNER_URL"],
        token=app.config["INTERNAL_API_TOKEN"],
        timeout=app.config["AI_PLANNER_TIMEOUT"],
    )

    _register_request_id(app)
    init_metrics(app)
    register_error_handlers(app)
    _register_blueprints(app)

    return app


def _register_blueprints(app):
    from app.blueprints.auth import bp as auth_bp
    from app.blueprints.ops import bp as ops_bp
    from app.blueprints.trips import bp as trips_bp
    from app.blueprints.users import bp as users_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(users_bp)
    app.register_blueprint(trips_bp)
    app.register_blueprint(ops_bp)


def _cors_origins(app):
    origins = app.config.get("CORS_ORIGINS", "*")
    if origins == "*":
        return "*"
    return [o.strip() for o in origins.split(",") if o.strip()]


def _register_request_id(app):
    @app.before_request
    def _assign_request_id():
        g.request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())

    @app.after_request
    def _return_request_id(response):
        if getattr(g, "request_id", None):
            response.headers["X-Request-ID"] = g.request_id
        return response
