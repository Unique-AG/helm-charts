#!/usr/bin/env bash
#
# Run the unique-jwt-auth specs inside the official Kong image.
#
# The plugin is mounted where Kong would install it, so `require
# "kong.plugins.unique-jwt-auth.<module>"` resolves the same way it does in a
# real gateway, and the specs run against the image's own OpenResty, cjson,
# resty.openssl and kong.plugins.jwt.jwt_parser rather than local substitutes.
#
# Usage: ./run.sh [kong-image-tag]

set -euo pipefail

KONG_IMAGE="${1:-kong/kong:3.3}"
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SPEC_DIR}/../../files/unique-jwt-auth" && pwd)"

exec docker run --rm \
  --entrypoint /usr/local/openresty/bin/resty \
  --volume "${PLUGIN_DIR}:/usr/local/share/lua/5.1/kong/plugins/unique-jwt-auth:ro" \
  --volume "${SPEC_DIR}:/spec:ro" \
  "${KONG_IMAGE}" \
  --errlog-level crit \
  /spec/run.lua
