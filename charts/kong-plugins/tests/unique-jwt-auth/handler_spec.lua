local runner = require "runner"
local mock_kong = require "mock_kong"

-- handler.lua captures the kong global at load time, so the mock has to be in
-- place before the require below. resty.http is also stubbed by mock_kong.
mock_kong.install()

local handler = require "kong.plugins.unique-jwt-auth.handler"
local build = require("token_builder").build

local describe = runner.describe
local it = runner.it
local assert_equal = runner.assert_equal
local assert_truthy = runner.assert_truthy
local assert_falsy = runner.assert_falsy
local assert_any_contains = runner.assert_any_contains

local ALLOWED_ISSUER = "https://id.example.com"
local ACCESS_TOKEN_SECRET = "offline-hs256-access-token-secret"
local UNKNOWN_ISSUER = "https://not-our-idp.example.com"
local RESOURCE_OWNER_CLAIM = "urn:zitadel:iam:user:resourceowner:id"
local RESOURCE_OWNER_NAME = "urn:zitadel:iam:user:resourceowner:name"
local PROJECT_ID = "project-abc"

local function conf(overrides)
    local base = {
        uri_param_names = {"token"},
        cookie_names = {},
        header_names = {"authorization"},
        claims_to_verify = {"exp"},
        allowed_iss = {ALLOWED_ISSUER},
        algorithm = "RS256",
        maximum_expiration = 0,
        consumer_match = false,
        run_on_preflight = true,
        security_warning_metric_name = "unique_jwt_auth_security_warnings_total",
        zitadel_project_id = PROJECT_ID,
        well_known_template = "%s/.well-known/openid-configuration",
        ssl_verify = false,
        introspection_enabled = false,
        introspection_timeout_ms = 2000
    }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return base
end

local function access_token(opts)
    opts = opts or {}
    local now = ngx.time()
    local claims = {
        iss = opts.iss or UNKNOWN_ISSUER,
        sub = "user-123",
        [RESOURCE_OWNER_CLAIM] = "company-456",
        exp = now + 3600
    }
    for key, value in pairs(opts.claims or {}) do
        claims[key] = value
    end
    for _, key in ipairs(opts.remove or {}) do
        claims[key] = nil
    end

    return build({
        typ = "JWT",
        alg = opts.alg or "RS256"
    }, claims, opts.secret or "irrelevant-these-never-reach-signature-checks")
end

local function verifiable_access_token(opts)
    opts = opts or {}
    opts.iss = opts.iss or ALLOWED_ISSUER
    opts.alg = opts.alg or "HS256"
    opts.secret = opts.secret or ACCESS_TOKEN_SECRET
    return access_token(opts)
end

local function verifiable_conf(overrides)
    local base = {
        algorithm = "HS256",
        allowed_iss = {ALLOWED_ISSUER}
    }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return conf(base)
end

local function introspection_conf(overrides)
    local base = {
        introspection_enabled = true,
        introspection_client_id = "realtime-api-client",
        introspection_client_secret = "realtime-api-secret"
    }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return conf(base)
end

local function well_known_response()
    return {
        status = 200,
        body = {
            introspection_endpoint = ALLOWED_ISSUER .. "/oauth/v2/introspect",
            jwks_uri = ALLOWED_ISSUER .. "/oauth/v2/keys"
        }
    }
end

local function active_introspection_body(overrides)
    local body = {
        active = true,
        iss = ALLOWED_ISSUER,
        sub = "user-123",
        [RESOURCE_OWNER_CLAIM] = "company-456",
        [RESOURCE_OWNER_NAME] = "Acme",
        ["urn:zitadel:iam:org:project:" .. PROJECT_ID .. ":roles"] = {
            admin = {
                ["org-1"] = "org-1"
            }
        }
    }
    for key, value in pairs(overrides or {}) do
        body[key] = value
    end
    return body
end

describe("JWT authentication", function()

    it("rejects a token from a disallowed issuer", function()
        local state = mock_kong.reset({
            headers = {
                authorization = "Bearer " .. access_token()
            }
        })

        handler:access(conf())

        assert_equal(401, state.response.status)
        assert_any_contains("disallowed issuer", state.warnings)
    end)

    it("accepts a verifiable access token from the Authorization header", function()
        local state = mock_kong.reset({
            headers = {
                authorization = "Bearer " .. verifiable_access_token()
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })

        handler:access(verifiable_conf())

        assert_falsy(state.response, "request should not have been rejected")
        assert_equal("user-123", state.upstream_headers["x-user-id"])
        assert_equal("company-456", state.upstream_headers["x-company-id"])
    end)

    it("accepts a verifiable JWT from the query string when introspection is off", function()
        local state = mock_kong.reset({
            query = {
                token = verifiable_access_token()
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })

        handler:access(verifiable_conf())

        assert_falsy(state.response, "request should not have been rejected")
        assert_equal("user-123", state.upstream_headers["x-user-id"])
        assert_equal(0, #state.http_calls, "JWT path must not call introspection")
    end)

    it("rejects multiple tokens", function()
        local state = mock_kong.reset({
            query = {
                token = verifiable_access_token()
            },
            headers = {
                authorization = "Bearer " .. verifiable_access_token({
                    claims = {
                        sub = "other-user"
                    }
                })
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })

        handler:access(verifiable_conf())

        assert_equal(401, state.response.status)
        assert_any_contains("Multiple tokens", state.warnings)
    end)

end)

describe("opaque query introspection", function()

    it("accepts an opaque query token and stamps identity headers", function()
        local state = mock_kong.reset({
            query = {
                token = "opaque-ws-token"
            },
            http_responses = {
                well_known_response(),
                {
                    status = 200,
                    body = active_introspection_body()
                }
            }
        })

        handler:access(introspection_conf())

        assert_falsy(state.response, "request should not have been rejected")
        assert_equal("user-123", state.upstream_headers["x-user-id"])
        assert_equal("company-456", state.upstream_headers["x-company-id"])
        assert_equal("Acme", state.upstream_headers["x-company-name"])
        assert_equal("admin", state.upstream_headers["x-user-roles"])
        assert_truthy(state.http_calls[2], "introspection POST should have been made")
        assert_any_contains("/oauth/v2/introspect", {state.http_calls[2].url})
    end)

    it("rejects an inactive introspected token", function()
        local state = mock_kong.reset({
            query = {
                token = "revoked-opaque-token"
            },
            http_responses = {
                well_known_response(),
                {
                    status = 200,
                    body = {
                        active = false
                    }
                }
            }
        })

        handler:access(introspection_conf())

        assert_equal(401, state.response.status)
        assert_any_contains("inactive introspected token", state.warnings)
    end)

    it("rejects when introspection transport fails", function()
        local state = mock_kong.reset({
            query = {
                token = "opaque-ws-token"
            },
            http_responses = {
                well_known_response(),
                {
                    err = "connection refused"
                }
            }
        })

        handler:access(introspection_conf())

        assert_equal(401, state.response.status)
        assert_any_contains("Introspection request failed", state.errors)
    end)

    it("keeps the JWT path for Authorization headers even when introspection is enabled", function()
        local state = mock_kong.reset({
            headers = {
                authorization = "Bearer " .. verifiable_access_token()
            },
            cache_keys = {ACCESS_TOKEN_SECRET},
            http_responses = {
                -- Must not be consumed; JWT path should not introspect.
                well_known_response()
            }
        })

        handler:access(introspection_conf({
            algorithm = "HS256"
        }))

        assert_falsy(state.response, "request should not have been rejected")
        assert_equal("user-123", state.upstream_headers["x-user-id"])
        assert_equal(0, #state.http_calls, "header credentials must not introspect")
    end)

    it("requires introspection client credentials when enabled", function()
        local state = mock_kong.reset({
            query = {
                token = "opaque-ws-token"
            }
        })

        handler:access(introspection_conf({
            introspection_client_id = "",
            introspection_client_secret = ""
        }))

        assert_equal(500, state.response.status)
        assert_any_contains("client credentials are not configured", state.errors)
    end)

end)
