#!/bin/sh
# Container entrypoint: prepares the Prometheus multiprocess dir, then runs CMD.
set -e

if [ -n "$PROMETHEUS_MULTIPROC_DIR" ]; then
  mkdir -p "$PROMETHEUS_MULTIPROC_DIR"
  rm -f "$PROMETHEUS_MULTIPROC_DIR"/* 2>/dev/null || true
fi

exec "$@"
