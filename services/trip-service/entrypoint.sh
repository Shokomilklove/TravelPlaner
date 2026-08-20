#!/bin/sh
# Container entrypoint: prepares the Prometheus multiprocess dir, runs DB
# migrations (retrying until the database is reachable), then hands off to CMD.
set -e

if [ -n "$PROMETHEUS_MULTIPROC_DIR" ]; then
  mkdir -p "$PROMETHEUS_MULTIPROC_DIR"
  rm -f "$PROMETHEUS_MULTIPROC_DIR"/* 2>/dev/null || true
fi

if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
  echo "Running database migrations..."
  n=0
  until flask db upgrade; do
    n=$((n + 1))
    if [ "$n" -ge 10 ]; then
      echo "Migrations failed after $n attempts" >&2
      exit 1
    fi
    echo "Migration attempt $n failed; database not ready, retrying in 3s..."
    sleep 3
  done
  echo "Migrations complete."
fi

exec "$@"
