#!/usr/bin/env bash

set -euo pipefail

BYTEPLUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

if ! git -C "${BYTEPLUS_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This script must be run inside a git checkout." >&2
  exit 1
fi

REPO_ROOT="$(git -C "${BYTEPLUS_DIR}" rev-parse --show-toplevel)"
ENV_FILE="${REPO_ROOT}/.env"
COMPOSE_DIR="${REPO_ROOT}/deployment/docker_compose"
COMPOSE_ENV_FILE="${COMPOSE_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Please copy .env.example to ${ENV_FILE} before running this deployment script." >&2
  exit 1
fi

HOST_PORT_FROM_ENV="$(read_env_value HOST_PORT || true)"
HOST_PORT="${HOST_PORT_FROM_ENV:-39000}"

echo "Fetching latest deploy branch..."
git -C "${REPO_ROOT}" fetch origin deploy
echo "Checking out deploy branch from origin/deploy..."
git -C "${REPO_ROOT}" checkout -B deploy origin/deploy

echo "Linking compose env file to root .env..."
ln -sfn "${ENV_FILE}" "${COMPOSE_ENV_FILE}"

cd "${COMPOSE_DIR}"

echo "Starting docker compose deployment..."
# Keep HOST_PORT aligned with the .env file so compose and the health check use the same port.
docker compose \
  --env-file "${ENV_FILE}" \
  -f docker-compose.yml \
  -f docker-compose.onyx-lite.yml \
  -f ../byteplus-lite/docker-compose.byteplus-lite.yml \
  up -d --build --remove-orphans

echo "Showing docker compose status..."
docker compose \
  --env-file "${ENV_FILE}" \
  -f docker-compose.yml \
  -f docker-compose.onyx-lite.yml \
  -f ../byteplus-lite/docker-compose.byteplus-lite.yml \
  ps

health_check_url="http://127.0.0.1:${HOST_PORT}/api/health"
echo "Running health check on ${health_check_url}..."
health_check_attempts=12
health_check_sleep_seconds=5
health_check_curl_max_time_seconds=10

for attempt in $(seq 1 "${health_check_attempts}"); do
  if curl --fail --silent --show-error --output /dev/null --connect-timeout 5 --max-time "${health_check_curl_max_time_seconds}" \
    "${health_check_url}"; then
    exit 0
  fi

  if [[ "${attempt}" -lt "${health_check_attempts}" ]]; then
    echo "Health check attempt ${attempt}/${health_check_attempts} failed; retrying in ${health_check_sleep_seconds}s..." >&2
    sleep "${health_check_sleep_seconds}"
  fi
done

echo "Health check failed after ${health_check_attempts} attempts: ${health_check_url}" >&2
exit 1
