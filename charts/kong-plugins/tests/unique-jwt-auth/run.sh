#!/usr/bin/env bash
#
# Run the unique-jwt-auth specs inside the official Kong image against a real
# Redis container, so atomic ticket consumption is exercised for real.
#
# Usage: ./run.sh [kong-image]

set -euo pipefail

# Digest-pinned so CI and local runs hit the same OpenResty/Kong/Redis bits.
# Bump tag and digest together by hand — this repo has no Renovate coverage
# for these test images. Override Kong with a positional argument when
# bisecting (e.g. ./run.sh kong/kong:3.4).
KONG_IMAGE="${1:-kong/kong:3.3@sha256:231de5c033386b87c09f2c6360e2b2de0b8072dffc9329c3600a3820479e4b8f}"
REDIS_IMAGE="${REDIS_IMAGE:-redis:7.2-alpine@sha256:05a97a479bc73de66f087dc05b569010772880f778cc8671fa6b8aadee32e5c6}"

SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SPEC_DIR}/../../files/unique-jwt-auth" && pwd)"

NETWORK="kong-plugin-test-$$"
REDIS_NAME="kong-plugin-test-redis-$$"

cleanup() {
  docker rm -f "${REDIS_NAME}" >/dev/null 2>&1 || true
  docker network rm "${NETWORK}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "${NETWORK}" >/dev/null

docker run -d --rm \
  --name "${REDIS_NAME}" \
  --network "${NETWORK}" \
  "${REDIS_IMAGE}" \
  >/dev/null

# Wait until Redis answers PING, then resolve its IP so the Kong container
# does not depend on Docker DNS inside OpenResty cosockets.
REDIS_IP=""
for _ in $(seq 1 50); do
  if docker run --rm --network "${NETWORK}" --entrypoint redis-cli "${REDIS_IMAGE}" \
      -h "${REDIS_NAME}" ping 2>/dev/null | grep -q PONG; then
    REDIS_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${REDIS_NAME}")"
    break
  fi
  sleep 0.2
done

if [[ -z "${REDIS_IP}" ]]; then
  echo "Redis did not become ready" >&2
  exit 1
fi

docker run --rm \
  --network "${NETWORK}" \
  --entrypoint /usr/local/openresty/bin/resty \
  --env "REDIS_HOST=${REDIS_IP}" \
  --env "REDIS_PORT=6379" \
  --volume "${PLUGIN_DIR}:/usr/local/share/lua/5.1/kong/plugins/unique-jwt-auth:ro" \
  --volume "${SPEC_DIR}:/spec:ro" \
  "${KONG_IMAGE}" \
  --errlog-level crit \
  /spec/run.lua
