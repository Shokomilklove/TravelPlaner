"""Internal-token authentication for service-to-service calls."""
import hmac
from functools import wraps

from flask import current_app, jsonify, request


def require_internal_token(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        provided = request.headers.get("X-Internal-Token", "")
        expected = current_app.config["INTERNAL_API_TOKEN"]
        if not provided or not hmac.compare_digest(provided, expected):
            return (
                jsonify(
                    {
                        "error": "unauthorized",
                        "message": "Invalid or missing internal token",
                    }
                ),
                401,
            )
        return fn(*args, **kwargs)

    return wrapper
