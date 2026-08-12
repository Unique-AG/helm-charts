local runner = require "runner"
local mock_kong = require "mock_kong"

-- handler.lua captures the kong global at load time.
mock_kong.install()

local handler = require "kong.plugins.unique-jwt-auth.handler"
local redis_store = require "kong.plugins.unique-jwt-auth.redis_store"
local ws_ticket = require "kong.plugins.unique-jwt-auth.ws_ticket"
local build = require("token_builder").build

local describe = runner.describe
local it = runner.it
local assert_equal = runner.assert_equal
local assert_truthy = runner.assert_truthy
local assert_falsy = runner.assert_falsy
local assert_any_contains = runner.assert_any_contains
local assert_none_contains = runner.assert_none_contains

local ALLOWED_ISSUER = "https://id.example.com"
local ACCESS_TOKEN_SECRET = "offline-hs256-access-token-secret"
local UNKNOWN_ISSUER = "https://not-our-idp.example.com"
local RESOURCE_OWNER_CLAIM = "urn:zitadel:iam:user:resourceowner:id"
local PROJECT_ID = "project-abc"
local TICKET_SCOPE = "ws:graphql"

local REDIS_HOST = os.getenv("REDIS_HOST") or "127.0.0.1"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT") or "6379")
-- Dedicated logical DB so specs can FLUSHDB without touching anything else.
local REDIS_DB = 15

local function redis_conf(overrides)
    local base = {
        redis_host = REDIS_HOST,
        redis_port = REDIS_PORT,
        redis_timeout_ms = 2000,
        redis_database = REDIS_DB,
        redis_key_prefix = "ws_ticket_test:",
        redis_ssl = false,
        ticket_scope = TICKET_SCOPE,
        ticket_ttl = 20,
        ticket_param_name = "ticket",
        ticket_mint_path = "/auth/ticket",
        ticket_mint_rate_limit = 0,
        ticket_fail_rate_limit = 0,
        ticket_allowed_origins = {},
        ws_ticket_enabled = true
    }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return base
end

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
        ws_ticket_enabled = false
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

local function ticket_conf(overrides)
    local base = redis_conf({
        algorithm = "HS256",
        allowed_iss = {ALLOWED_ISSUER},
        uri_param_names = {"token"},
        cookie_names = {},
        header_names = {"authorization"},
        claims_to_verify = {"exp"},
        maximum_expiration = 0,
        consumer_match = false,
        run_on_preflight = true,
        security_warning_metric_name = "unique_jwt_auth_security_warnings_total",
        zitadel_project_id = PROJECT_ID,
        well_known_template = "%s/.well-known/openid-configuration",
        ssl_verify = false
    })
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return base
end

local function upgrade_headers(extra)
    local headers = {
        upgrade = "websocket",
        connection = "Upgrade"
    }
    for key, value in pairs(extra or {}) do
        headers[key] = value
    end
    return headers
end

local function flush_redis(conf_table)
    local redis = require "resty.redis"
    local red = redis:new()
    red:set_timeout(2000)
    local ok, err = red:connect(conf_table.redis_host, conf_table.redis_port)
    if not ok then
        error("redis connect to " .. tostring(conf_table.redis_host) .. ":" ..
            tostring(conf_table.redis_port) .. " failed: " .. tostring(err))
    end
    local db = conf_table.redis_database or REDIS_DB
    local sok, serr = red:select(db)
    if not sok then
        red:close()
        error("redis SELECT failed: " .. tostring(serr))
    end
    local fok, ferr = red:flushdb()
    if not fok then
        red:close()
        error("redis FLUSHDB failed: " .. tostring(ferr))
    end
    red:set_keepalive(10000, 10)
end

local function run()

describe("JWT authentication (token path regression)", function()

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

    it("accepts a verifiable JWT from ?token= with tickets disabled", function()
        local state = mock_kong.reset({
            query = {
                token = verifiable_access_token()
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })

        handler:access(verifiable_conf({
            ws_ticket_enabled = false
        }))

        assert_falsy(state.response, "request should not have been rejected")
        assert_equal("user-123", state.upstream_headers["x-user-id"])
    end)

    it("accepts a verifiable JWT from ?token= with tickets enabled", function()
        -- Backward compatibility: ?token= must keep working when tickets are on.
        local state = mock_kong.reset({
            query = {
                token = verifiable_access_token()
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })

        handler:access(ticket_conf())

        assert_falsy(state.response, "request should not have been rejected")
        assert_equal("user-123", state.upstream_headers["x-user-id"])
        assert_equal("company-456", state.upstream_headers["x-company-id"])
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

describe("ticket mint", function()

    it("rejects mint without Authorization Bearer", function()
        flush_redis(ticket_conf())
        local state = mock_kong.reset({
            method = "POST",
            path = "/auth/ticket",
            query = {
                token = verifiable_access_token()
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })

        handler:access(ticket_conf())

        assert_equal(401, state.response.status)
        assert_any_contains("missing Authorization Bearer", state.warnings)
    end)

    it("rejects mint with an invalid JWT", function()
        flush_redis(ticket_conf())
        local state = mock_kong.reset({
            method = "POST",
            path = "/auth/ticket",
            headers = {
                authorization = "Bearer " .. access_token()
            }
        })

        handler:access(ticket_conf())

        assert_equal(401, state.response.status)
        assert_any_contains("disallowed issuer", state.warnings)
    end)

    it("rejects mint when identity claims are missing", function()
        flush_redis(ticket_conf())
        local state = mock_kong.reset({
            method = "POST",
            path = "/auth/ticket",
            headers = {
                authorization = "Bearer " .. verifiable_access_token({
                    remove = {RESOURCE_OWNER_CLAIM}
                })
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })

        handler:access(ticket_conf())

        assert_equal(401, state.response.status)
        assert_any_contains("missing claim", state.warnings)
    end)

    it("mints an opaque ticket, stores only its hash, and never proxies", function()
        local cfg = ticket_conf()
        flush_redis(cfg)
        local state = mock_kong.reset({
            method = "POST",
            path = "/auth/ticket",
            headers = {
                authorization = "Bearer " .. verifiable_access_token()
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })

        handler:access(cfg)

        assert_equal(200, state.response.status)
        assert_equal("no-store", state.response.headers["Cache-Control"])
        assert_truthy(state.response.body.ticket, "ticket missing from response")
        assert_equal(20, state.response.body.expires_in)

        -- Opaque: not a JWT (no two dots).
        local dots = 0
        for _ in state.response.body.ticket:gmatch("%.") do
            dots = dots + 1
        end
        assert_equal(0, dots, "ticket must not be a JWT")

        -- Raw ticket must not be stored; only the hash key may exist.
        local hash = ws_ticket._sha256_hex(state.response.body.ticket)
        local redis = require "resty.redis"
        local red = redis:new()
        red:set_timeout(2000)
        assert(red:connect(cfg.redis_host, cfg.redis_port))
        assert(red:select(cfg.redis_database))
        local raw_hit = red:get(cfg.redis_key_prefix .. state.response.body.ticket)
        assert_equal(ngx.null, raw_hit, "raw ticket must not be a Redis key")
        local stored = red:get(cfg.redis_key_prefix .. ws_ticket._ticket_key(hash))
        assert_truthy(stored and stored ~= ngx.null, "hash key missing")
        assert_none_contains(state.response.body.ticket, {stored}, "raw ticket must not appear in the record")
        assert_none_contains("eyJ", {stored}, "JWT material must not appear in the record")
        red:set_keepalive(10000, 10)
    end)

    it("rate-limits minting per subject", function()
        local cfg = ticket_conf({
            ticket_mint_rate_limit = 2
        })
        flush_redis(cfg)

        for i = 1, 2 do
            local state = mock_kong.reset({
                method = "POST",
                path = "/auth/ticket",
                headers = {
                    authorization = "Bearer " .. verifiable_access_token()
                },
                cache_keys = {ACCESS_TOKEN_SECRET}
            })
            handler:access(cfg)
            assert_equal(200, state.response.status, "mint " .. i .. " should succeed")
        end

        local state = mock_kong.reset({
            method = "POST",
            path = "/auth/ticket",
            headers = {
                authorization = "Bearer " .. verifiable_access_token()
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })
        handler:access(cfg)
        assert_equal(429, state.response.status)
        assert_any_contains("rate-limited", state.warnings)
    end)

    it("fails closed with 503 when Redis is unreachable on mint", function()
        local cfg = ticket_conf({
            redis_host = "127.0.0.1",
            redis_port = 1 -- nothing listening
        })
        local state = mock_kong.reset({
            method = "POST",
            path = "/auth/ticket",
            headers = {
                authorization = "Bearer " .. verifiable_access_token()
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })

        handler:access(cfg)

        assert_equal(503, state.response.status)
        assert_any_contains("Redis error", state.errors)
    end)

end)

describe("ticket consume", function()

    local function mint_ticket(cfg)
        local state = mock_kong.reset({
            method = "POST",
            path = "/auth/ticket",
            headers = {
                authorization = "Bearer " .. verifiable_access_token()
            },
            cache_keys = {ACCESS_TOKEN_SECRET}
        })
        handler:access(cfg)
        assert_equal(200, state.response.status, "mint for consume setup")
        return state.response.body.ticket
    end

    it("accepts a mint → upgrade round trip and strips the ticket param", function()
        local cfg = ticket_conf()
        flush_redis(cfg)
        local ticket = mint_ticket(cfg)

        local state = mock_kong.reset({
            method = "GET",
            path = "/graphql",
            query = {
                ticket = ticket,
                foo = "bar"
            },
            headers = upgrade_headers()
        })

        handler:access(cfg)

        assert_falsy(state.response, "upgrade should not have been rejected")
        assert_equal("user-123", state.upstream_headers["x-user-id"])
        assert_equal("company-456", state.upstream_headers["x-company-id"])
        assert_truthy(state.cleared_headers["x-user-roles"])
        assert_truthy(state.cleared_headers["x-company-name"])
        assert_truthy(state.cleared_headers["x-company-domain"])
        assert_truthy(state.query_set, "ticket query arg should have been rewritten")
        assert_falsy(state.query_set.ticket, "ticket must be stripped before proxy")
        assert_equal("bar", state.query_set.foo)
    end)

    it("rejects a second consume of the same ticket (single-use)", function()
        local cfg = ticket_conf()
        flush_redis(cfg)
        local ticket = mint_ticket(cfg)

        local first = mock_kong.reset({
            query = {
                ticket = ticket
            },
            headers = upgrade_headers()
        })
        handler:access(cfg)
        assert_falsy(first.response, "first consume should succeed")

        local second = mock_kong.reset({
            query = {
                ticket = ticket
            },
            headers = upgrade_headers()
        })
        handler:access(cfg)
        assert_equal(401, second.response.status)
        assert_any_contains("unknown/expired/replayed", second.warnings)
    end)

    it("rejects a ticket on a non-upgrade request without touching Redis after the check", function()
        local cfg = ticket_conf()
        flush_redis(cfg)
        local ticket = mint_ticket(cfg)

        local state = mock_kong.reset({
            query = {
                ticket = ticket
            },
            headers = {
                -- no Upgrade
            }
        })
        handler:access(cfg)
        assert_equal(401, state.response.status)
        assert_any_contains("non-upgrade", state.warnings)

        -- Ticket must still be consumable afterwards (Redis was not drained).
        local retry = mock_kong.reset({
            query = {
                ticket = ticket
            },
            headers = upgrade_headers()
        })
        handler:access(cfg)
        assert_falsy(retry.response, "ticket should still be valid after non-upgrade rejection")
    end)

    it("rejects a ticket with the wrong scope without burning it", function()
        local mint_cfg = ticket_conf({
            ticket_scope = "ws:chat"
        })
        flush_redis(mint_cfg)
        local ticket = mint_ticket(mint_cfg)

        local consume_cfg = ticket_conf({
            ticket_scope = "ws:speech"
        })
        local state = mock_kong.reset({
            query = {
                ticket = ticket
            },
            headers = upgrade_headers()
        })
        handler:access(consume_cfg)
        assert_equal(401, state.response.status)
        assert_any_contains("scope mismatch", state.warnings)

        -- The misrouted attempt must not have consumed the ticket: it must
        -- still work on the route with the scope it was minted for.
        local retry = mock_kong.reset({
            query = {
                ticket = ticket
            },
            headers = upgrade_headers()
        })
        handler:access(mint_cfg)
        assert_falsy(retry.response, "ticket should still be valid for its own scope")
        assert_equal("user-123", retry.upstream_headers["x-user-id"])
    end)

    it("rejects a disallowed Origin", function()
        local cfg = ticket_conf({
            ticket_allowed_origins = {"https://app.example.com"}
        })
        flush_redis(cfg)
        local ticket = mint_ticket(cfg)

        local state = mock_kong.reset({
            query = {
                ticket = ticket
            },
            headers = upgrade_headers({
                origin = "https://evil.example.com"
            })
        })
        handler:access(cfg)
        assert_equal(401, state.response.status)
        assert_any_contains("Origin rejected", state.warnings)
    end)

    it("accepts an exact-match Origin", function()
        local cfg = ticket_conf({
            ticket_allowed_origins = {"https://app.example.com"}
        })
        flush_redis(cfg)
        local ticket = mint_ticket(cfg)

        local state = mock_kong.reset({
            query = {
                ticket = ticket
            },
            headers = upgrade_headers({
                origin = "https://app.example.com"
            })
        })
        handler:access(cfg)
        assert_falsy(state.response, "exact Origin should be accepted")
        assert_equal("user-123", state.upstream_headers["x-user-id"])
    end)

    it("does not fall through to the token path when ?ticket= is present", function()
        local cfg = ticket_conf()
        flush_redis(cfg)

        local state = mock_kong.reset({
            query = {
                ticket = "forged-ticket",
                token = verifiable_access_token()
            },
            headers = upgrade_headers(),
            cache_keys = {ACCESS_TOKEN_SECRET}
        })
        handler:access(cfg)

        assert_equal(401, state.response.status)
        -- Must not have stamped identity from the JWT fallback.
        assert_falsy(state.upstream_headers["x-user-id"])
    end)

    it("fails closed with 503 when Redis is unreachable on consume", function()
        local cfg = ticket_conf({
            redis_host = "127.0.0.1",
            redis_port = 1
        })
        local state = mock_kong.reset({
            query = {
                ticket = "anything"
            },
            headers = upgrade_headers()
        })
        handler:access(cfg)
        assert_equal(503, state.response.status)
    end)

end)

describe("atomic consume", function()

    it("returns the record once and misses on the second consume", function()
        -- redis_store.consume uses a single EVAL (GET+DEL). Redis executes
        -- EVAL atomically, so two concurrent consumers cannot both win; this
        -- spec proves the script removes the key on first success.
        local cfg = ticket_conf()
        flush_redis(cfg)

        local claims = {
            sub = "user-123",
            [RESOURCE_OWNER_CLAIM] = "company-456"
        }
        local ticket, mint_result = ws_ticket.mint(cfg, claims)
        if not ticket then
            error("mint failed: " .. tostring(mint_result and mint_result.reason))
        end

        local hash = ws_ticket._sha256_hex(ticket)
        local key = ws_ticket._ticket_key(hash)

        -- A wrong-scope consume must reject WITHOUT deleting the record.
        local burned, berr = redis_store.consume(cfg, key, "ws:other")
        assert_falsy(burned, "wrong-scope consume must not return the record")
        assert_equal("scope mismatch", berr)

        local first, ferr = redis_store.consume(cfg, key, cfg.ticket_scope)
        if not first then
            error("first consume should return the record: " .. tostring(ferr))
        end

        local second, serr = redis_store.consume(cfg, key, cfg.ticket_scope)
        assert_falsy(second, "second consume must not return a record")
        assert_equal("not found", serr)
    end)

    it("sets a TTL on rate-limit counters atomically", function()
        -- INCR+EXPIRE run as one EVAL: the counter must never exist without
        -- a TTL, or the rate limit would never reset.
        local cfg = ticket_conf()
        flush_redis(cfg)

        local count, err = redis_store.incr_with_expiry(cfg, "mint:ttl-spec", 60)
        if not count then
            error("incr_with_expiry failed: " .. tostring(err))
        end
        assert_equal(1, count)

        local redis = require "resty.redis"
        local red = redis:new()
        red:set_timeout(2000)
        assert(red:connect(cfg.redis_host, cfg.redis_port))
        assert(red:select(cfg.redis_database))
        local ttl = red:ttl(cfg.redis_key_prefix .. "mint:ttl-spec")
        red:set_keepalive(10000, 10)
        assert_truthy(ttl and ttl > 0 and ttl <= 60,
            "rate-limit counter must carry a TTL, got " .. tostring(ttl))
    end)

end)

end -- run()

return run
