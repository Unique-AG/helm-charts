-------------------------------------------------------------------------------
-- A stand-in for the `kong` PDK global, plus a resty.http stub for
-- introspection specs.
--
-- handler.lua captures `local kong = kong` at load time, so the global has to
-- exist before the plugin is required and must keep the same identity for the
-- whole run. install() therefore creates it once and reset() swaps the mutable
-- state behind it between specs.
-------------------------------------------------------------------------------

local cjson = require "cjson.safe"

local M = {}

local state

local function new_state(options)
    options = options or {}
    return {
        method = options.method or "GET",
        path = options.path or "/graphql",
        query = options.query or {},
        headers = options.headers or {},
        forwarded_ip = options.forwarded_ip or "10.0.0.1",
        credential = options.credential,
        -- When set, kong.cache:get returns this keyset without calling the
        -- loader callback, so HS256 specs can pass Zitadel verification offline.
        cache_keys = options.cache_keys,
        -- Introspection HTTP stub. Each entry is consumed in order.
        -- { status, body = table|string, err = string|nil }
        http_responses = options.http_responses or {},
        http_calls = {},
        -- observations
        upstream_headers = {},
        cleared_headers = {},
        warnings = {},
        errors = {},
        response = nil
    }
end

local function install_http_stub()
    package.loaded["resty.http"] = {
        new = function()
            return {
                set_timeout = function()
                end,
                request_uri = function(_, url, opts)
                    state.http_calls[#state.http_calls + 1] = {
                        url = url,
                        opts = opts
                    }
                    local next_response = table.remove(state.http_responses, 1)
                    if not next_response then
                        return nil, "http stub has no queued responses"
                    end
                    if next_response.err then
                        return nil, next_response.err
                    end
                    local body = next_response.body
                    if type(body) == "table" then
                        body = cjson.encode(body)
                    end
                    return {
                        status = next_response.status or 200,
                        body = body or ""
                    }
                end
            }
        end
    }
end

--- Install the mock as the `kong` global. Call before requiring the plugin.
function M.install()
    state = new_state()
    install_http_stub()

    local function record_response(status, body, headers)
        state.response = {
            status = status,
            body = body,
            headers = headers
        }
        return state.response
    end

    _G.kong = {
        request = {
            get_method = function()
                return state.method
            end,
            get_path = function()
                return state.path
            end,
            get_query = function()
                return state.query
            end,
            get_headers = function()
                return state.headers
            end
        },
        response = {
            exit = record_response
        },
        service = {
            request = {
                set_header = function(name, value)
                    state.upstream_headers[name] = value
                end,
                clear_header = function(name)
                    state.cleared_headers[name] = true
                    state.upstream_headers[name] = nil
                end
            }
        },
        client = {
            get_forwarded_ip = function()
                return state.forwarded_ip
            end,
            get_credential = function()
                return state.credential
            end,
            authenticate = function()
            end
        },
        cache = {
            get = function(_, key, _, cb, ...)
                if state.cache_keys then
                    return {
                        keys = state.cache_keys,
                        updated_at = ngx.time()
                    }
                end
                -- Endpoint discovery and similar loaders go through the callback.
                if cb then
                    return cb(...)
                end
                return nil, "kong.cache stub has no cache_keys and no loader for " .. tostring(key)
            end,
            invalidate = function()
            end
        },
        log = {
            debug = function()
            end,
            notice = function()
            end,
            info = function()
            end,
            warn = function(message)
                state.warnings[#state.warnings + 1] = tostring(message)
            end,
            err = function(message)
                state.errors[#state.errors + 1] = tostring(message)
            end
        },
        ctx = {
            shared = {}
        }
    }

    return M
end

--- Start a fresh request. Returns the observation table for assertions.
function M.reset(options)
    state = new_state(options)
    _G.kong.ctx.shared = {}
    return state
end

function M.state()
    return state
end

return M
