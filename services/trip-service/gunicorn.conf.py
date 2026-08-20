"""Gunicorn configuration (production WSGI server)."""
import multiprocessing
import os

bind = f"0.0.0.0:{os.environ.get('PORT', '5001')}"
workers = int(os.environ.get("GUNICORN_WORKERS", "1"))
threads = int(os.environ.get("GUNICORN_THREADS", "2"))
worker_class = "gthread"
timeout = int(os.environ.get("GUNICORN_TIMEOUT", "120"))
accesslog = "-"
errorlog = "-"
loglevel = os.environ.get("LOG_LEVEL", "info").lower()


def child_exit(server, worker):
    """Clean up Prometheus multiprocess metrics when a worker exits."""
    if os.environ.get("PROMETHEUS_MULTIPROC_DIR"):
        try:
            from prometheus_client import multiprocess

            multiprocess.mark_process_dead(worker.pid)
        except Exception:
            pass
