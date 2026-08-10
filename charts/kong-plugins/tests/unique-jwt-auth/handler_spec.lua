local runner = require "runner"
local mock_kong = require "mock_kong"

-- handler.lua captures the kong global at load time, so the mock has to be in
-- place before the require below.
mock_kong.install()

local handler = require "kong.plugins.unique-jwt-auth.handler"
local build = require("token_builder").build

local describe = runner.describe
local it = runner.it
local assert_equal = runner.assert_equal
local assert_truthy = runner.assert_truthy
local assert_falsy = runner.assert_falsy
local assert_any_contains = runner.assert_any_contains
local assert_none_contains = runner.assert_none_contains

local TICKET_SECRET = "shared-across-every-gateway-replica"
local TICKET_ISSUER = "kong-ws-ticket"
local MINT_PATH = "/auth/ws-ticket"
local ALLOWED_ISSUER = "https://id.example.com"
local ACCESS_TOKEN_SECRET = "offline-hs256-access-token-secret"
-- Anything outside allowed_iss fails on the very first Zitadel check, which
-- keeps the specs away from a JWKS fetch while still proving that a request
-- reached the access-token path.
local UNKNOWN_ISSUER = "https://not-our-idp.example.com"
local DISALLOWED_ISSUER_LOG = "disallowed issuer"
local RESOURCE_OWNER_CLAIM = "urn:zitadel:iam:user:resourceowner:id"

local function conf(overrides)
    local base = {
        uri_param_names = {"token"},
        cookie_names = {},
        header_names = {"authorization"},
        claims_to_verify = {"exp"},
        allowed_iss = {"https://id.example.com"},
        algorithm = "RS256",
        maximum_expiration = 0,
        consumer_match = false,
        run_on_preflight = true,
        security_warning_metric_name = "unique_jwt_auth_security_warnings_total",
        ws_ticket_enabled = true,
        ws_ticket_secret = TICKET_SECRET,
        ws_ticket_ttl = 60,
        ws_ticket_issuer = TICKET_ISSUER,
        ws_ticket_audience = "chat",
        ws_ticket_mint_path = MINT_PATH,
        reject_jwt_in_query = false
    }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return base
end

--- Build a ticket. opts.claims overrides claims, opts.remove drops them.
local function ticket(opts)
    opts = opts or {}
    local now = ngx.time()
    local claims = {
        iss = TICKET_ISSUER,
        sub = "user-123",
        cid = "company-456",
        aud = "chat",
        iat = now,
        nbf = now - 5,
        exp = now + 60,
        jti = "0123456789abcdef"
    }
    for key, value in pairs(opts.claims or {}) do
        claims[key] = value
    end
    for _, key in ipairs(opts.remove or {}) do
        claims[key] = nil
    end

    return build(opts.header or {
        typ = "JWT",
        alg = "HS256"
    }, claims, opts.secret or TICKET_SECRET)
end

--- Build something shaped like a Zitadel access token.
---
--- opts.claims overrides claims, opts.remove drops them, opts.iss / opts.alg /
--- opts.secret override the defaults. Rejection-path specs keep the unknown
--- issuer and a placeholder secret; mint success specs use ALLOWED_ISSUER,
--- HS256 and ACCESS_TOKEN_SECRET with the cache stub.
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

--- Plugin config that lets verify_zitadel_token succeed offline via the
--- kong.cache stub and an HS256 access token signed with ACCESS_TOKEN_SECRET.
local function mintable_conf(overrides)
    local base = {
        algorithm = "HS256",
        allowed_iss = {ALLOWED_ISSUER},
        well_known_template = "%s/.well-known/openid-configuration"
    }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return conf(base)
end

local function verifiable_access_token(opts)
    opts = opts or {}
    opts.iss = opts.iss or ALLOWED_ISSUER
    opts.alg = opts.alg or "HS256"
    opts.secret = opts.secret or ACCESS_TOKEN_SECRET
    return access_token(opts)
end

describe("ticket authentication", function()

    it("accepts a ticket from the query string", function()
        local state = mock_kong.reset({
            query = {
                token = ticket()
            }
        })

        handler:access(conf())

        assert_falsy(state.response, "request should not have been rejected")
        assert_equal("user-123", state.upstream_headers["x-user-id"])
        assert_equal("company-456", state.upstream_headers["x-company-id"])
    end)

    it("clears every identity header a ticket cannot vouch for", function()
        local state = mock_kong.reset({
            query = {
                token = ticket()
            }
        })

        handler:access(conf())

        assert_truthy(state.cleared_headers["x-user-roles"], "x-user-roles must be cleared")
        assert_truthy(state.cleared_headers["x-company-name"], "x-company-name must be cleared")
        assert_truthy(state.cleared_headers["x-company-domain"], "x-company-domain must be cleared")
    end)

    it("ignores a roles claim smuggled into a ticket", function()
        local state = mock_kong.reset({
            query = {
                token = ticket({
                    claims = {
                        ["urn:zitadel:iam:org:project:abc:roles"] = {
                            admin = {}
                        }
                    }
                })
            }
        })

        handler:access(conf())

        assert_falsy(state.upstream_headers["x-user-roles"], "no roles may be proxied upstream")
    end)

    it("rejects a ticket signed with a foreign secret", function()
        local state = mock_kong.reset({
            query = {
                token = ticket({
                    secret = "forged"
                })
            }
        })

        handler:access(conf())

        assert_equal(401, state.response.status)
        assert_any_contains("WebSocket ticket with invalid signature", state.warnings)
    end)

    it("rejects a ticket presented with a mismatched algorithm header", function()
        local state = mock_kong.reset({
            query = {
                token = ticket({
                    header = {
                        typ = "JWT",
                        alg = "RS256"
                    }
                })
            }
        })

        handler:access(conf())

        assert_equal(401, state.response.status)
        assert_any_contains("WebSocket ticket with unexpected algorithm", state.warnings)
    end)

    it("rejects an expired ticket", function()
        local now = ngx.time()
        local state = mock_kong.reset({
            query = {
                token = ticket({
                    claims = {
                        iat = now - 600,
                        nbf = now - 600,
                        exp = now - 300
                    }
                })
            }
        })

        handler:access(conf())

        assert_equal(401, state.response.status)
        assert_any_contains("WebSocket ticket claims validation failed", state.warnings)
    end)

    it("rejects a ticket that is not yet valid", function()
        local now = ngx.time()
        local state = mock_kong.reset({
            query = {
                token = ticket({
                    claims = {
                        nbf = now + 300,
                        exp = now + 600
                    }
                })
            }
        })

        handler:access(conf())

        assert_equal(401, state.response.status)
    end)

    it("rejects a ticket minted for another audience", function()
        local state = mock_kong.reset({
            query = {
                token = ticket({
                    claims = {
                        aud = "speech"
                    }
                })
            }
        })

        handler:access(conf())

        assert_equal(401, state.response.status)
        assert_any_contains("WebSocket ticket with unexpected audience", state.warnings)
    end)

    it("rejects a ticket with no company id", function()
        local state = mock_kong.reset({
            query = {
                token = ticket({
                    remove = {"cid"}
                })
            }
        })

        handler:access(conf())

        assert_equal(401, state.response.status)
        assert_any_contains("WebSocket ticket without identity claims", state.warnings)
    end)

    it("never hands a ticket to other plugins as an access token", function()
        mock_kong.reset({
            query = {
                token = ticket()
            }
        })

        handler:access(conf())

        assert_falsy(kong.ctx.shared.unique_jwt_token, "a ticket is not an access token")
        assert_truthy(kong.ctx.shared.unique_ws_ticket)
    end)

    it("treats a ticket as an ordinary token when the feature is off", function()
        local state = mock_kong.reset({
            query = {
                token = ticket()
            }
        })

        handler:access(conf({
            ws_ticket_enabled = false
        }))

        assert_equal(401, state.response.status)
        assert_any_contains(DISALLOWED_ISSUER_LOG, state.warnings)
    end)

end)

describe("reject_jwt_in_query", function()

    it("rejects an access token in the query string when enabled", function()
        local state = mock_kong.reset({
            query = {
                token = access_token()
            }
        })

        handler:access(conf({
            reject_jwt_in_query = true
        }))

        assert_equal(401, state.response.status)
        assert_any_contains("access token presented as a query parameter", state.warnings)
        assert_none_contains(DISALLOWED_ISSUER_LOG, state.warnings, "should reject before validating the token")
    end)

    it("leaves access tokens in the Authorization header alone", function()
        local state = mock_kong.reset({
            headers = {
                authorization = "Bearer " .. access_token()
            }
        })

        handler:access(conf({
            reject_jwt_in_query = true
        }))

        assert_any_contains(DISALLOWED_ISSUER_LOG, state.warnings, "should reach the normal access-token path")
        assert_none_contains("query parameter", state.warnings)
    end)

    it("still accepts tickets in the query string", function()
        local state = mock_kong.reset({
            query = {
                token = ticket()
            }
        })

        handler:access(conf({
            reject_jwt_in_query = true
        }))

        assert_falsy(state.response, "tickets are the whole point of the flag")
        assert_equal("user-123", state.upstream_headers["x-user-id"])
    end)

    it("allows access tokens in the query string while disabled", function()
        local state = mock_kong.reset({
            query = {
                token = access_token()
            }
        })

        handler:access(conf())

        assert_any_contains(DISALLOWED_ISSUER_LOG, state.warnings, "should reach the normal access-token path")
        assert_none_contains("query parameter", state.warnings)
    end)

end)

describe("ticket mint endpoint", function()

    it("rejects a mint request with no credential", function()
        local state = mock_kong.reset({
            method = "POST",
            path = MINT_PATH
        })

        handler:access(conf())

        assert_equal(401, state.response.status)
    end)

    it("refuses to mint from a token in the query string", function()
        local state = mock_kong.reset({
            method = "POST",
            path = MINT_PATH,
            query = {
                token = access_token()
            }
        })

        handler:access(conf())

        assert_equal(401, state.response.status)
        assert_any_contains("ticket mint without an Authorization header", state.warnings)
    end)

    it("refuses to mint a ticket from another ticket", function()
        local state = mock_kong.reset({
            method = "POST",
            path = MINT_PATH,
            headers = {
                authorization = "Bearer " .. ticket()
            }
        })

        handler:access(conf())

        assert_equal(401, state.response.status)
        assert_any_contains("ticket mint attempted with a ticket", state.warnings)
    end)

    it("verifies the access token exactly as the normal path does", function()
        local state = mock_kong.reset({
            method = "POST",
            path = MINT_PATH,
            headers = {
                authorization = "Bearer " .. access_token()
            }
        })

        handler:access(conf())

        assert_equal(401, state.response.status)
        assert_any_contains(DISALLOWED_ISSUER_LOG, state.warnings)
    end)

    it("rejects a mint request carrying two different tokens", function()
        local state = mock_kong.reset({
            method = "POST",
            path = MINT_PATH,
            headers = {
                authorization = "Bearer " .. access_token()
            },
            query = {
                token = ticket()
            }
        })

        handler:access(conf())

        assert_equal(401, state.response.status)
        assert_any_contains("Multiple tokens", state.warnings)
    end)

    it("prefers the header when the same token is sent twice", function()
        local same = ticket()
        local state = mock_kong.reset({
            method = "POST",
            path = MINT_PATH,
            headers = {
                authorization = "Bearer " .. same
            },
            query = {
                token = same
            }
        })

        handler:access(conf())

        assert_equal(401, state.response.status)
        assert_any_contains("ticket mint attempted with a ticket", state.warnings)
        assert_none_contains("without an Authorization header", state.warnings)
    end)

    it("only intercepts POST, so a GET on the same path authenticates normally", function()
        local state = mock_kong.reset({
            method = "GET",
            path = MINT_PATH,
            query = {
                token = ticket()
            }
        })

        handler:access(conf())

        assert_falsy(state.response, "GET should fall through to normal authentication")
        assert_equal("user-123", state.upstream_headers["x-user-id"])
    end)

    it("does not intercept anything while the feature is off", function()
        local state = mock_kong.reset({
            method = "POST",
            path = MINT_PATH,
            headers = {
                authorization = "Bearer " .. access_token()
            }
        })

        handler:access(conf({
            ws_ticket_enabled = false
        }))

        assert_any_contains(DISALLOWED_ISSUER_LOG, state.warnings)
        assert_none_contains("ticket mint", state.warnings)
    end)

    it("mints a ticket that authenticates a subsequent upgrade", function()
        local mint_state = mock_kong.reset({
            method = "POST",
            path = MINT_PATH,
            headers = {
                authorization = "Bearer " .. verifiable_access_token()
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })

        handler:access(mintable_conf())

        assert_equal(200, mint_state.response.status)
        assert_equal(60, mint_state.response.body.expires_in)
        assert_truthy(mint_state.response.body.ticket, "mint should return a ticket")
        assert_equal(0, #mint_state.errors)

        local upgrade_state = mock_kong.reset({
            query = {
                token = mint_state.response.body.ticket
            }
        })

        handler:access(conf())

        assert_falsy(upgrade_state.response, "minted ticket should authenticate the upgrade")
        assert_equal("user-123", upgrade_state.upstream_headers["x-user-id"])
        assert_equal("company-456", upgrade_state.upstream_headers["x-company-id"])
    end)

    it("returns 401 when a verified token is missing sub", function()
        local state = mock_kong.reset({
            method = "POST",
            path = MINT_PATH,
            headers = {
                authorization = "Bearer " .. verifiable_access_token({
                    remove = {"sub"}
                })
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })

        handler:access(mintable_conf())

        assert_equal(401, state.response.status)
        assert_any_contains("access token missing 'sub'", state.warnings)
        assert_equal(0, #state.errors, "client claim gaps must not look like gateway faults")
    end)

    it("returns 401 when a verified token is missing the resourceowner claim", function()
        local state = mock_kong.reset({
            method = "POST",
            path = MINT_PATH,
            headers = {
                authorization = "Bearer " .. verifiable_access_token({
                    remove = {RESOURCE_OWNER_CLAIM}
                })
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })

        handler:access(mintable_conf())

        assert_equal(401, state.response.status)
        assert_any_contains("access token missing '" .. RESOURCE_OWNER_CLAIM .. "'", state.warnings)
        assert_equal(0, #state.errors, "client claim gaps must not look like gateway faults")
    end)

    it("still returns 500 when signing itself fails", function()
        local state = mock_kong.reset({
            method = "POST",
            path = MINT_PATH,
            headers = {
                authorization = "Bearer " .. verifiable_access_token()
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })

        handler:access(mintable_conf({
            ws_ticket_secret = ""
        }))

        assert_equal(500, state.response.status)
        assert_any_contains("Could not mint WebSocket ticket", state.errors)
    end)

end)
