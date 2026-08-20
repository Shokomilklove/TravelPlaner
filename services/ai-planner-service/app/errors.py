"""Centralised JSON error handling."""
from flask import jsonify
from werkzeug.exceptions import HTTPException


def register_error_handlers(app):
    @app.errorhandler(HTTPException)
    def handle_http(err):
        return (
            jsonify(
                {
                    "error": (err.name or "error").lower().replace(" ", "_"),
                    "message": err.description,
                }
            ),
            err.code or 500,
        )

    @app.errorhandler(Exception)
    def handle_unexpected(err):  # pragma: no cover - defensive
        app.logger.exception("unhandled exception")
        return (
            jsonify(
                {"error": "internal_error", "message": "An unexpected error occurred"}
            ),
            500,
        )
