-------------------------------------------------------------------------------
-- A stand-in for the `kong` PDK global.
--
-- handler.lua captures `local kong = kong` at load time, so the global has to
-- exist before the plugin is required and must keep the same identity for the
-- whole run. install() therefore creates it once and reset() swaps the mutable
-- state behind it between specs.
--
-- Only the surface the plugin actually touches is implemented. Anything the
-- ticket paths do not reach (consumers, cache, worker events) is deliberately
-- absent so that a spec straying into it fails loudly rather than silently
-- passing against a stub.
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
        -- observations
        upstream_headers = {},
        cleared_headers = {},
        warnings = {},
        errors = {},
        response = nil
    }
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
