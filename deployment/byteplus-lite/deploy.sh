#!/usr/bin/env bash

set -euo pipefail

BYTEPLUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${BYTEPLUS_DIR}/.env"

read_env_value() {
  local key="$1"

  awk -v key="$key" '
    /^[[:space:]]*($|#)/ { next }
    {
      line = $0
      sub(/^[[:space:]]*export[[:space:]]+/, "", line)

      pos = index(line, "=")
      if (pos == 0) {
        next
      }

      current_key = substr(line, 1, pos - 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", current_key)
      if (current_key != key) {
        next
      }

      value = substr(line, pos + 1)
      sub(/[[:space:]]+#.*$/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["'\''"]|["'\''"]$/, "", value)
      print value
      exit
    }
  ' "${ENV_FILE}"
}

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Please create it before running this deployment script." >&2
  exit 1
fi

if ! git -C "${BYTEPLUS_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This script must be run inside a git checkout." >&2
  exit 1
fi

REPO_ROOT="$(git -C "${BYTEPLUS_DIR}" rev-parse --show-toplevel)"
COMPOSE_DIR="${REPO_ROOT}/deployment/docker_compose"
HOST_PORT_FROM_ENV="$(read_env_value HOST_PORT || true)"
HOST_PORT="${HOST_PORT_FROM_ENV:-39000}"

echo "Fetching latest deploy branch..."
git -C "${REPO_ROOT}" fetch origin deploy
echo "Checking out deploy branch..."
git -C "${REPO_ROOT}" checkout deploy
echo "Fast-forwarding from origin/deploy..."
git -C "${REPO_ROOT}" merge --ff-only origin/deploy

cd "${COMPOSE_DIR}"

echo "Starting docker compose deployment..."
docker compose \
  --env-file "${BYTEPLUS_DIR}/.env" \
  -f docker-compose.yml \
  -f docker-compose.onyx-lite.yml \
  -f ../byteplus-lite/docker-compose.byteplus-lite.yml \
  up -d --build --remove-orphans

echo "Showing docker compose status..."
docker compose \
  --env-file "${BYTEPLUS_DIR}/.env" \
  -f docker-compose.yml \
  -f docker-compose.onyx-lite.yml \
  -f ../byteplus-lite/docker-compose.byteplus-lite.yml \
  ps

echo "Running health check on http://127.0.0.1:${HOST_PORT}..."
curl --fail --silent --show-error --head --connect-timeout 5 --max-time 10 \
  "http://127.0.0.1:${HOST_PORT}"
