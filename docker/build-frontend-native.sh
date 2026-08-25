#!/usr/bin/env bash
# Native host build for the custom Highlight frontend image.
#
# Why: docker/build-frontend-custom.sh runs the full monorepo `yarn install`
# inside the build container and OOMs on Docker Desktop's default 8GB memory
# cap (Highlight's monorepo + transitive deps is huge). This script does the
# yarn install + vite build on the host (which has more RAM), then bakes the
# static output into a slim nginx image via docker/frontend-prebuilt.Dockerfile.
#
# Usage:
#   1. Fill in client IDs in docker/.env.frontend-build (gitignored)
#   2. ./docker/build-frontend-native.sh <tag>     e.g. v0.5.6-wremit-1
#   3. docker push ghcr.io/workremits/highlight-frontend:<tag>

set -euo pipefail

TAG="${1:?usage: $0 <tag>   e.g. v0.5.6-wremit-1}"
ENV_FILE="${ENV_FILE:-docker/.env.frontend-build}"
REGISTRY="${REGISTRY:-ghcr.io/workremits}"
IMAGE="${REGISTRY}/highlight-frontend:${TAG}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "missing ${ENV_FILE} -- copy docker/.env.frontend-build.example and fill in"
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

# Vite reads these via import.meta.env; turbo.json's build env allowlist
# already includes them so they propagate from the host shell to the vite build.

echo "==> yarn install (full monorepo; idempotent if already installed)"
yarn install --immutable

echo "==> building frontend via turbo (builds internal deps first, then frontend)"
echo "    SLACK_CLIENT_ID=${SLACK_CLIENT_ID:0:8}…   (full value hidden)"

# CRITICAL: The runtime entrypoint script (docker/frontend-entrypoint.py) does
# string replacement on the built bundle. For that to work, the bundle must
# contain the Highlight Cloud placeholder URLs as LITERAL strings -- otherwise
# Vite falls back to window.location.origin-based defaults and the entrypoint
# regex never matches. Match these defaults to the ones in frontend-entrypoint.py.
export REACT_APP_AUTH_MODE=firebase
export REACT_APP_FRONTEND_URI=https://app.highlight.io
export REACT_APP_PRIVATE_GRAPH_URI=https://pri.highlight.io
export REACT_APP_PUBLIC_GRAPH_URI=https://pub.highlight.io
export REACT_APP_OTLP_ENDPOINT=https://otel.highlight.io:4318
export REACT_APP_DISABLE_ANALYTICS=false
# Without REACT_APP_IN_DOCKER=true, the Highlight dashboard self-instruments
# and records the operator's UI sessions into their own project (frontend/src/
# index.tsx:152 -- H.start() runs unless isOnPrem is truthy, and isOnPrem
# requires both Vite's PROD flag AND this env var).
export REACT_APP_IN_DOCKER=true

# yarn build:frontend = turbo run build --filter @highlight-run/frontend...
# The trailing ... is critical: it pulls in packages/ui, sdk/highlight-run, etc.
# so their typegen + build artifacts exist before the frontend types:check runs.
yarn build:frontend

if [[ ! -d "frontend/build" ]]; then
  echo "build did not produce frontend/build/" >&2
  exit 1
fi

echo "==> docker build slim image ${IMAGE}"
docker build \
  --file docker/frontend-prebuilt.Dockerfile \
  --tag "${IMAGE}" \
  .

echo "==> Built ${IMAGE}"
echo "Push with:   docker push ${IMAGE}"
