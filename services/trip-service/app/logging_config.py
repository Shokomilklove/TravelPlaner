"""Structured JSON logging.

Emits one JSON object per log line to stdout so a log shipper (ELK / Loki)
can ingest it directly. Request context (request id, method, path) is attached
automatically when available.
"""
import logging
import sys

from flask import g, has_request_context, request
from pythonjsonlogger import jsonlogger


class ContextFilter(logging.Filter):
    def __init__(self, service_name):
        super().__init__()
        self.service_name = service_name

    def filter(self, record):
        record.service = self.service_name
        if has_request_context():
            record.request_id = getattr(g, "request_id", None)
            record.method = request.method
            record.path = request.path
        else:
            record.request_id = None
            record.method = None
            record.path = None
        return True


def configure_logging(app):
    log_level = str(app.config.get("LOG_LEVEL", "INFO")).upper()

    handler = logging.StreamHandler(sys.stdout)
    formatter = jsonlogger.JsonFormatter(
        "%(asctime)s %(levelname)s %(name)s %(service)s %(message)s "
        "%(request_id)s %(method)s %(path)s",
        rename_fields={"asctime": "timestamp", "levelname": "level", "name": "logger"},
    )
    handler.setFormatter(formatter)
    handler.addFilter(ContextFilter(app.config["SERVICE_NAME"]))

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(log_level)

    app.logger.setLevel(log_level)
    # Route werkzeug/gunicorn logs through the same JSON handler.
    for name in ("werkzeug", "gunicorn.error", "gunicorn.access"):
        lg = logging.getLogger(name)
        lg.handlers.clear()
        lg.propagate = True
