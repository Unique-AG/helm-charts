-------------------------------------------------------------------------------
-- Zitadel token introspection for opaque query-string credentials.
--
-- Used on WebSocket upgrades where the browser cannot send Authorization
-- headers. Results are never cached: revocation is the security control, and
-- caching would delay it. The introspection endpoint URL itself is cached via
-- kong.cache because the well-known document rarely changes.
-------------------------------------------------------------------------------

local http = require("resty.http")
local cjson = require("cjson.safe")
local zitadel_keys = require "kong.plugins.unique-jwt-auth.zitadel_keys"
local validate_issuer = require"kong.plugins.unique-jwt-auth.validate_issuers".validate_issuer

local encode_base64 = ngx.encode_base64

local _M = {}

local function unauthorized(reason, message)
    return nil, {
        status = 401,
        message = message or "Unauthorized",
        reason = reason
    }
end

local function load_introspection_endpoint(well_known_endpoint, conf)
    local httpc = http.new()
    httpc:set_timeout(conf.introspection_timeout_ms or 2000)

    local res, err = httpc:request_uri(well_known_endpoint, {
        method = "GET",
        headers = conf.well_known_extra_headers or {},
        ssl_verify = conf.ssl_verify
    })
    if err then
        return nil, err
    end
    if not res or res.status ~= 200 then
        return nil, "well-known endpoint returned " .. tostring(res and res.status)
    end

    local body, decode_err = cjson.decode(res.body)
    if decode_err then
        return nil, decode_err
    end

    local endpoint = body.introspection_endpoint
    if type(endpoint) ~= "string" or endpoint == "" then
        return nil, "introspection_endpoint missing from well-known response"
    end
    if conf.ssl_verify and endpoint:sub(1, 8) ~= "https://" then
        return nil, "introspection_endpoint must use HTTPS when ssl_verify is enabled"
    end

    return endpoint
end

local function resolve_introspection_endpoint(conf, issuer)
    local well_known_endpoint = zitadel_keys.get_wellknown_endpoint(conf.well_known_template, issuer)
    local cache_key = "unique_jwt_auth_introspection_endpoint:" .. well_known_endpoint
    local endpoint, err = kong.cache:get(cache_key, nil, load_introspection_endpoint, well_known_endpoint, conf)
    if err then
        return nil, err
    end
    return endpoint
end

--- Introspect `token` against Zitadel. Returns claims on success, or nil + err.
-- err = { status = number, message = string, reason = string|nil }
function _M.introspect(conf, token)
    if type(conf.introspection_client_id) ~= "string" or conf.introspection_client_id == "" or
        type(conf.introspection_client_secret) ~= "string" or conf.introspection_client_secret == "" then
        kong.log.err("introspection_enabled but client credentials are not configured")
        return nil, {
            status = 500,
            message = "An unexpected error occurred during authentication",
            reason = "introspection_error"
        }
    end

    local issuer = conf.allowed_iss and conf.allowed_iss[1]
    if type(issuer) ~= "string" or issuer == "" then
        kong.log.err("introspection_enabled but allowed_iss is empty")
        return nil, {
            status = 500,
            message = "An unexpected error occurred during authentication",
            reason = "introspection_error"
        }
    end

    local endpoint, endpoint_err = resolve_introspection_endpoint(conf, issuer)
    if not endpoint then
        kong.log.err("Failed to resolve introspection endpoint: " .. tostring(endpoint_err))
        return unauthorized("introspection_error")
    end

    local httpc = http.new()
    httpc:set_timeout(conf.introspection_timeout_ms or 2000)

    local basic = encode_base64(conf.introspection_client_id .. ":" .. conf.introspection_client_secret)
    local res, err = httpc:request_uri(endpoint, {
        method = "POST",
        body = "token=" .. ngx.escape_uri(token) .. "&token_type_hint=access_token",
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Authorization"] = "Basic " .. basic
        },
        ssl_verify = conf.ssl_verify
    })

    if err then
        kong.log.err("Introspection request failed: " .. tostring(err))
        return unauthorized("introspection_error")
    end
    if not res or res.status ~= 200 then
        kong.log.warn("Introspection endpoint returned " .. tostring(res and res.status) .. " from " ..
                          (kong.client.get_forwarded_ip() or "unknown"))
        return unauthorized("introspection_error")
    end

    local body, decode_err = cjson.decode(res.body)
    if decode_err or type(body) ~= "table" then
        kong.log.err("Failed to decode introspection response: " .. tostring(decode_err))
        return unauthorized("introspection_error")
    end

    if body.active ~= true then
        kong.log.warn("Rejected inactive introspected token from " .. (kong.client.get_forwarded_ip() or "unknown"))
        return unauthorized("introspection_inactive")
    end

    if body.iss and not validate_issuer(conf.allowed_iss, body) then
        kong.log.warn("Rejected introspected token with disallowed issuer: " .. tostring(body.iss) .. " from " ..
                          (kong.client.get_forwarded_ip() or "unknown"))
        return unauthorized("disallowed_issuer")
    end

    if type(body.sub) ~= "string" or body.sub == "" then
        kong.log.warn("Introspected token missing sub from " .. (kong.client.get_forwarded_ip() or "unknown"))
        return unauthorized("introspection_inactive")
    end

    return body
end

return _M
