#!/usr/bin/env bash

set -euo pipefail

KONG_IMAGE="${1:-kong:3.9.1@sha256:76c14b93e989f7f4418039f7f9789ca32564016211c86ac1a18022f4788e7b9c}"
REDIS_IMAGE="${REDIS_IMAGE:-redis:7.2-alpine@sha256:ccd6aa8d45ff3f033d6fa15b8cc1a50579f65c89f38cf9bb607a954c4f2128ed}"
CLUSTER_USER="ws-ticket-test"
CLUSTER_PASSWORD="cluster-password"
# Least-privilege user holding only the documented ticket commands. It has no
# access to the server INFO command, so it guards against reintroducing a fatal
# version probe during cluster initialization.
MINIMAL_USER="ws-ticket-minimal"
MINIMAL_PASSWORD="minimal-password"
KEY_PREFIX="ws_ticket_test:"

SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SPEC_DIR}/../../files/unique-jwt-auth" && pwd)"

NETWORK="kong-plugin-test-$$"
SINGLE_NAME="kong-plugin-single-$$"
CLUSTER_NAMES=(
  "kong-plugin-cluster-1-$$"
  "kong-plugin-cluster-2-$$"
  "kong-plugin-cluster-3-$$"
)

cleanup() {
  docker rm -f "${SINGLE_NAME}" "${CLUSTER_NAMES[@]}" >/dev/null 2>&1 || true
  docker network rm "${NETWORK}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

redis_cli() {
  docker run --rm --network "${NETWORK}" --entrypoint redis-cli \
    "${REDIS_IMAGE}" "$@"
}

wait_for_redis() {
  local host="$1"
  for _ in $(seq 1 100); do
    if [[ "$(redis_cli -h "${host}" ping 2>/dev/null || true)" == "PONG" ]]; then
      return
    fi
    sleep 0.2
  done
  echo "Redis ${host} did not become ready" >&2
  exit 1
}

docker network create "${NETWORK}" >/dev/null

docker run -d --rm \
  --name "${SINGLE_NAME}" \
  --network "${NETWORK}" \
  "${REDIS_IMAGE}" >/dev/null

for name in "${CLUSTER_NAMES[@]}"; do
  docker run -d --rm \
    --name "${name}" \
    --network "${NETWORK}" \
    "${REDIS_IMAGE}" \
    redis-server \
      --cluster-enabled yes \
      --cluster-config-file nodes.conf \
      --cluster-node-timeout 5000 \
      --appendonly no \
      --protected-mode no >/dev/null
done

wait_for_redis "${SINGLE_NAME}"
for name in "${CLUSTER_NAMES[@]}"; do
  wait_for_redis "${name}"
done

SINGLE_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${SINGLE_NAME}")"
CLUSTER_IPS=()
for name in "${CLUSTER_NAMES[@]}"; do
  CLUSTER_IPS+=("$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${name}")")
done

redis_cli --cluster create \
  "${CLUSTER_IPS[0]}:6379" \
  "${CLUSTER_IPS[1]}:6379" \
  "${CLUSTER_IPS[2]}:6379" \
  --cluster-replicas 0 \
  --cluster-yes >/dev/null

for ip in "${CLUSTER_IPS[@]}"; do
  redis_cli -h "${ip}" ACL SETUSER "${CLUSTER_USER}" on \
    ">${CLUSTER_PASSWORD}" allcommands allkeys >/dev/null

  redis_cli -h "${ip}" ACL SETUSER "${MINIMAL_USER}" on \
    ">${MINIMAL_PASSWORD}" resetkeys "~${KEY_PREFIX}*" nocommands \
    +cluster\|slots +cluster\|nodes +cluster\|info +asking +set +getdel \
    >/dev/null
done

cluster_ready=false
for _ in $(seq 1 100); do
  cluster_info="$(redis_cli -h "${CLUSTER_IPS[0]}" cluster info 2>/dev/null || true)"
  if [[ "${cluster_info}" == *"cluster_state:ok"* ]]; then
    cluster_ready=true
    break
  fi
  sleep 0.2
done

if [[ "${cluster_ready}" != "true" ]]; then
  echo "Redis Cluster did not become ready" >&2
  exit 1
fi

CLUSTER_NODES="$(IFS=,; echo "${CLUSTER_IPS[*]}")"

docker run --rm \
  --network "${NETWORK}" \
  --entrypoint /usr/local/openresty/bin/resty \
  --volume "${PLUGIN_DIR}:/usr/local/share/lua/5.1/kong/plugins/unique-jwt-auth:ro" \
  --volume "${SPEC_DIR}:/spec:ro" \
  "${KONG_IMAGE}" \
  --errlog-level crit \
  /spec/shared_dict_guard.lua

docker run --rm \
  --network "${NETWORK}" \
  --entrypoint /usr/local/openresty/bin/resty \
  --env "REDIS_HOST=${SINGLE_IP}" \
  --env "REDIS_PORT=6379" \
  --env "REDIS_CLUSTER_NODES=${CLUSTER_NODES}" \
  --env "REDIS_CLUSTER_USER=${CLUSTER_USER}" \
  --env "REDIS_CLUSTER_PASSWORD=${CLUSTER_PASSWORD}" \
  --env "REDIS_CLUSTER_MINIMAL_USER=${MINIMAL_USER}" \
  --env "REDIS_CLUSTER_MINIMAL_PASSWORD=${MINIMAL_PASSWORD}" \
  --volume "${PLUGIN_DIR}:/usr/local/share/lua/5.1/kong/plugins/unique-jwt-auth:ro" \
  --volume "${SPEC_DIR}:/spec:ro" \
  "${KONG_IMAGE}" \
  --shdict 'redis_cluster_slot_locks 1m' \
  --errlog-level crit \
  /spec/run.lua
