#!/usr/bin/env bash
#
# Run the unique-jwt-auth specs inside the official Kong image.
#
# The plugin is mounted where Kong would install it, so `require
# "kong.plugins.unique-jwt-auth.<module>"` resolves the same way it does in a
# real gateway, and the specs run against the image's own OpenResty, cjson,
# resty.openssl and kong.plugins.jwt.jwt_parser rather than local substitutes.
#
# Usage: ./run.sh [kong-image]

set -euo pipefail

# Digest-pinned so CI and local runs hit the same OpenResty/Kong bits. Bump the
# tag and digest together by hand — this repo has no Renovate coverage for the
# test image. Override with a positional argument when bisecting against another
# version (e.g. ./run.sh kong/kong:3.4).
KONG_IMAGE="${1:-kong/kong:3.3@sha256:231de5c033386b87c09f2c6360e2b2de0b8072dffc9329c3600a3820479e4b8f}"
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SPEC_DIR}/../../files/unique-jwt-auth" && pwd)"

exec docker run --rm \
  --entrypoint /usr/local/openresty/bin/resty \
  --volume "${PLUGIN_DIR}:/usr/local/share/lua/5.1/kong/plugins/unique-jwt-auth:ro" \
  --volume "${SPEC_DIR}:/spec:ro" \
  "${KONG_IMAGE}" \
  --errlog-level crit \
  /spec/run.lua
