#!/usr/bin/env bash
# Build a custom Highlight frontend image with self-hosted OAuth client IDs.
# Replaces the doppler-dependent build path with a plain env-file build.
#
# Why this exists:
#   The official ghcr.io/highlight/highlight-frontend image is built with
#   Highlight Cloud's own OAuth client IDs baked into the JS bundle (Vite
#   resolves import.meta.env.* at build time). Self-hosters cannot use the
#   official image for any third-party integration. This script lets you bake
#   YOUR client IDs into a custom image.
#
# Usage:
#   1. Fill in client IDs in docker/.env.frontend-build (gitignored)
#   2. ./docker/build-frontend-custom.sh <tag>     e.g. v0.5.6-wremit-1
#   3. docker push ghcr.io/workremits/highlight-frontend:<tag>
#   4. Update compose.coolify.yml to use the custom image
#
# Required env file: docker/.env.frontend-build
#   SLACK_CLIENT_ID=...
#   # add LINEAR_CLIENT_ID, GITHUB_CLIENT_ID, etc. when you wire those up

set -euo pipefail

TAG="${1:?usage: $0 <tag>   e.g. v0.5.6-wremit-1}"
ENV_FILE="${ENV_FILE:-docker/.env.frontend-build}"
REGISTRY="${REGISTRY:-ghcr.io/workremits}"
IMAGE="${REGISTRY}/highlight-frontend:${TAG}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "missing ${ENV_FILE} -- copy docker/.env.frontend-build.example and fill in"
  exit 1
fi

# Load the env file so docker build can see the vars as build args
set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

echo "==> Building ${IMAGE}"
echo "==> Using SLACK_CLIENT_ID=${SLACK_CLIENT_ID:0:8}…   (full value hidden)"

# Run yarn build with the OAuth env vars exposed, then bake into nginx image.
# We avoid the upstream Dockerfile because it hard-requires doppler.
docker build \
  --file docker/frontend-custom.Dockerfile \
  --build-arg SLACK_CLIENT_ID="${SLACK_CLIENT_ID:-}" \
  --build-arg LINEAR_CLIENT_ID="${LINEAR_CLIENT_ID:-}" \
  --build-arg GITHUB_CLIENT_ID="${GITHUB_CLIENT_ID:-}" \
  --build-arg JIRA_CLIENT_ID="${JIRA_CLIENT_ID:-}" \
  --build-arg DISCORD_CLIENT_ID="${DISCORD_CLIENT_ID:-}" \
  --build-arg CLICKUP_CLIENT_ID="${CLICKUP_CLIENT_ID:-}" \
  --build-arg GITLAB_CLIENT_ID="${GITLAB_CLIENT_ID:-}" \
  --build-arg HEIGHT_CLIENT_ID="${HEIGHT_CLIENT_ID:-}" \
  --build-arg MICROSOFT_TEAMS_BOT_ID="${MICROSOFT_TEAMS_BOT_ID:-}" \
  --tag "${IMAGE}" \
  .

echo "==> Built ${IMAGE}"
echo "Push with:   docker push ${IMAGE}"
