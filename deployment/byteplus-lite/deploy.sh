#!/usr/bin/env bash

set -euo pipefail

BYTEPLUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${BYTEPLUS_DIR}/.env"

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

git -C "${REPO_ROOT}" fetch origin deploy
git -C "${REPO_ROOT}" checkout deploy
git -C "${REPO_ROOT}" merge --ff-only origin/deploy

cd "${COMPOSE_DIR}"

docker compose \
  --env-file "${BYTEPLUS_DIR}/.env" \
  -f docker-compose.yml \
  -f docker-compose.onyx-lite.yml \
  -f ../byteplus-lite/docker-compose.byteplus-lite.yml \
  up -d --build --remove-orphans

docker compose \
  --env-file "${BYTEPLUS_DIR}/.env" \
  -f docker-compose.yml \
  -f docker-compose.onyx-lite.yml \
  -f ../byteplus-lite/docker-compose.byteplus-lite.yml \
  ps

curl -I "http://127.0.0.1:${HOST_PORT:-39000}"
