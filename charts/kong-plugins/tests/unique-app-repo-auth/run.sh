#!/usr/bin/env bash

set -euo pipefail

KONG_IMAGE="${1:-kong:3.9.1@sha256:76c14b93e989f7f4418039f7f9789ca32564016211c86ac1a18022f4788e7b9c}"

SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SPEC_DIR}/../../files/unique-app-repo-auth" && pwd)"
# Shared harness, mounted alongside /spec because Docker cannot nest a file
# mount inside a read-only bind.
SHARED_DIR="$(cd "${SPEC_DIR}/.." && pwd)"

# The specs exercise pure Lua, so this needs no Redis and no shared dict — only
# the Kong image's resty and its cjson.
docker run --rm \
  --entrypoint /usr/local/openresty/bin/resty \
  --volume "${PLUGIN_DIR}:/usr/local/share/lua/5.1/kong/plugins/unique-app-repo-auth:ro" \
  --volume "${SPEC_DIR}:/spec:ro" \
  --volume "${SHARED_DIR}:/shared:ro" \
  "${KONG_IMAGE}" \
  --errlog-level crit \
  /spec/run.lua
