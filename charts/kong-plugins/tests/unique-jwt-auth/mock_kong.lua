-------------------------------------------------------------------------------
-- Stand-in for the `kong` PDK global.
--
-- handler.lua captures `local kong = kong` at load time, so the global must
-- exist before the plugin is required and keep the same identity for the run.
-- install() creates it once; reset() swaps mutable state between specs.
-------------------------------------------------------------------------------

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
        -- loader, so HS256 specs can pass Zitadel verification offline.
        cache_keys = options.cache_keys,
        upstream_headers = {},
        cleared_headers = {},
        query_set = nil,
        warnings = {},
        errors = {},
        response = nil
    }
end

local function header_value(name)
    local value = state.headers[name] or state.headers[name:lower()]
    return value
end

local function concat_log_args(...)
    local n = select("#", ...)
    if n == 0 then
        return ""
    end
    local parts = {}
    for i = 1, n do
        parts[i] = tostring(select(i, ...))
    end
    return table.concat(parts)
end

--- Install the mock as the `kong` global. Call before requiring the plugin.
function M.install()
    state = new_state()

    local function record_response(status, body, headers)
        state.response = {
            status = status,
            body = body,
            headers = headers
        }
        -- kong.response.exit never returns in production; in specs the caller
        -- sees the returned table and stops further handler work.
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
            end,
            get_header = function(name)
                return header_value(name)
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
                end,
                set_query = function(args)
                    state.query_set = args
                    state.query = args
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
            warn = function(...)
                state.warnings[#state.warnings + 1] = concat_log_args(...)
            end,
            err = function(...)
                state.errors[#state.errors + 1] = concat_log_args(...)
            end
        },
        ctx = {
            shared = {}
        },
        worker_events = {
            register = function()
            end
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
