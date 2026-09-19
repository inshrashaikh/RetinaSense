#!/bin/sh
# RetinaSense all-in-one container entrypoint (nginx + uvicorn in one image).
#
# Renders the nginx config from the shared template, runs uvicorn (FastAPI,
# :8000) in the background, and moves nginx to the foreground so the container
# stays alive and receives SIGTERM on `docker stop`.
set -eu

# Default: backend reachable on loopback (same container). Compose sets this to
# the dedicated backend service name when deployed as separate containers.
export BACKEND_PROXY_TARGET="${BACKEND_PROXY_TARGET:-127.0.0.1}"

echo "[entrypoint] rendering nginx config (backend target: ${BACKEND_PROXY_TARGET})"
envsubst '$BACKEND_PROXY_TARGET' \
  < /etc/nginx/templates/default.conf.template \
  > /etc/nginx/conf.d/default.conf

echo "[entrypoint] starting uvicorn on 0.0.0.0:8000"
uvicorn app.main:app --app-dir /app --host 0.0.0.0 --port 8000 --workers 1 \
  --log-level info &

echo "[entrypoint] starting nginx (SPA + /api proxy)"
exec nginx -g 'daemon off;'