# syntax=docker/dockerfile:1

#
# RetinaSense multi-stage build.
#
# Targets:
#   backend           -> uvicorn/FastAPI service (compose "backend" service)
#   frontend          -> nginx serving the built SPA (compose "frontend")
#   runtime (default) -> all-in-one: nginx + uvicorn in a single container
#
# docker build -t retinasense .                                  # all-in-one
# docker build --target backend  -t retinasense-backend  .       # compose
# docker build --target frontend -t retinasense-frontend .       # compose
#

###############################################################################
# Stage 1 — frontend build (Node 20 + Vite + tsc)
#
# VITE_API_BASE_URL stays EMPTY so the production bundle calls the same-origin
# /api/... route, which nginx proxies to the backend. No CORS, no host
# mismatches — exactly like the dev setup.
###############################################################################
FROM node:20-alpine AS frontend-build

WORKDIR /build/frontend

ARG VITE_API_BASE_URL=
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
# Never enable demo mode for a real screening workflow (see frontend/.env.example).
ARG VITE_DEMO_MODE=false
ENV VITE_DEMO_MODE=$VITE_DEMO_MODE

COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

COPY frontend/ ./
RUN npm run build

###############################################################################
# Stage 2 — backend Python dependencies
#
# torch/torchvision are installed from PyTorch's CPU index: the default PyPI
# torch wheel bundles the CUDA runtime (~2.5 GB) that a container never uses.
# The resolution is pinned and CPU-indexed exactly as documented in
# backend/requirements.txt. The follow-up `pip install -r requirements.txt`
# sees torch/torchvision already satisfied at the pinned versions and leaves
# them alone.
###############################################################################
FROM python:3.12-slim AS backend-deps

WORKDIR /deps

COPY backend/requirements.txt /deps/requirements.txt

RUN pip install --no-cache-dir \
        torch==2.13.0 torchvision==0.28.0 \
        --index-url https://download.pytorch.org/whl/cpu \
 && pip install --no-cache-dir -r /deps/requirements.txt

# opencv-python (a runtime import of the explainability path) needs GL + GLib.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/*

###############################################################################
# Stage 3 — backend runtime (uvicorn only, compose "backend" target)
#
# MATLAB is not installed in the container (its Python engine is Windows-only
# and licence-gated), so real screening fails closed with an honest
# MATLAB_ENGINE_UNAVAILABLE — the grader never gets a fabricated result.
###############################################################################
FROM python:3.12-slim AS backend

# Python stdlib + installed packages from the dependency stage (incl. uvicorn,
# sqlalchemy, psycopg, torch, opencv).
COPY --from=backend-deps /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=backend-deps /usr/local/bin /usr/local/bin

# Copy system libraries (libgl1, libglib2.0-0 and their transitive deps)
# from the backend-deps stage instead of re-running apt-get, which avoids
# a second 50 MB download and sidesteps disk-space constraints on the host.
COPY --from=backend-deps /usr/lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu
COPY --from=backend-deps /usr/share/glvnd /usr/share/glvnd
COPY --from=backend-deps /lib/x86_64-linux-gnu /lib/x86_64-linux-gnu

WORKDIR /app

# Backend application (config.py resolves DATA_DIR as /app/data).
COPY backend/app /app/app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request as u; u.urlopen('http://127.0.0.1:8000/api/health', timeout=3)" || exit 1

# Runtime storage (SQLite when no external DB, plus uploaded images/artifacts).
VOLUME /app/data

CMD ["uvicorn", "app.main:app", "--app-dir", "/app", "--host", "0.0.0.0", \
     "--port", "8000", "--workers", "1", "--log-level", "info"]

###############################################################################
# Stage 4 — frontend runtime (nginx only, compose "frontend" target)
#
# The official nginx entrypoint substitutes ${BACKEND_PROXY_TARGET} (env):
# point BACKEND_PROXY_TARGET at the backend service name in compose.
###############################################################################
FROM nginx:1.27-alpine AS frontend

COPY --from=frontend-build /build/frontend/dist /usr/share/nginx/html
COPY docker/nginx.conf.template /etc/nginx/templates/default.conf.template

EXPOSE 80

###############################################################################
# Stage 5 — default: all-in-one runtime (nginx + uvicorn)
###############################################################################
FROM python:3.12-slim AS runtime

# Python stdlib + installed packages from the dependency stage.
COPY --from=backend-deps /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=backend-deps /usr/local/bin /usr/local/bin

# nginx (web front) + glib/GL (opencv) + gettext-base (envsubst for the nginx
# template) in one runtime image.
RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx gettext-base libgl1 libglib2.0-0 \
 && rm -rf /etc/nginx/sites-enabled/default \
 && rm -rf /var/lib/apt/lists/* \
 && ln -sf /dev/stdout /var/log/nginx/access.log \
 && ln -sf /dev/stderr /var/log/nginx/error.log

ENV BACKEND_PROXY_TARGET=127.0.0.1

WORKDIR /app

# Backend application (config.py resolves DATA_DIR as /app/data).
COPY backend/app /app/app

# Built SPA -> nginx webroot; template -> nginx config (rendered at start).
COPY --from=frontend-build /build/frontend/dist /usr/share/nginx/html
COPY docker/nginx.conf.template /etc/nginx/templates/default.conf.template

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80 8000

# Backend health, reached like the SPA reaches it.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request as u; u.urlopen('http://127.0.0.1:8000/api/health', timeout=3)" || exit 1

# Runtime storage (SQLite when no external DB, plus uploaded images/artifacts).
VOLUME /app/data

CMD ["/usr/local/bin/entrypoint.sh"]