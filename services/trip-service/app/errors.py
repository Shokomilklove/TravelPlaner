"""Centralised JSON error handling."""
from flask import jsonify
from marshmallow import ValidationError
from werkzeug.exceptions import HTTPException


def register_error_handlers(app):
    @app.errorhandler(ValidationError)
    def handle_validation(err):
        return (
            jsonify(
                {
                    "error": "validation_error",
                    "message": "Invalid request",
                    "details": err.messages,
                }
            ),
            400,
        )

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
