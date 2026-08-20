"""Gunicorn configuration (production WSGI server)."""
import multiprocessing
import os

bind = f"0.0.0.0:{os.environ.get('PORT', '5002')}"
workers = int(os.environ.get("GUNICORN_WORKERS", multiprocessing.cpu_count() * 2 + 1))
threads = int(os.environ.get("GUNICORN_THREADS", "2"))
worker_class = "gthread"
# Generous timeout: LLM calls can take a while.
timeout = int(os.environ.get("GUNICORN_TIMEOUT", "180"))
accesslog = "-"
errorlog = "-"
loglevel = os.environ.get("LOG_LEVEL", "info").lower()


def child_exit(server, worker):
    if os.environ.get("PROMETHEUS_MULTIPROC_DIR"):
        try:
            from prometheus_client import multiprocess

            multiprocess.mark_process_dead(worker.pid)
        except Exception:
            pass
