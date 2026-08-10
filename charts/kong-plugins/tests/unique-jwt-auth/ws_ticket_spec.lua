local runner = require "runner"
local jwt_parser = require "kong.plugins.jwt.jwt_parser"
local ws_ticket = require "kong.plugins.unique-jwt-auth.ws_ticket"

local describe = runner.describe
local it = runner.it
local assert_equal = runner.assert_equal
local assert_truthy = runner.assert_truthy
local assert_falsy = runner.assert_falsy
local assert_contains = runner.assert_contains

local SECRET = "shared-across-every-gateway-replica"

local function conf(overrides)
    local base = {
        ws_ticket_secret = SECRET,
        ws_ticket_ttl = 60,
        ws_ticket_issuer = "kong-ws-ticket",
        ws_ticket_audience = "chat"
    }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return base
end

local function access_token_claims(overrides, remove)
    local base = {
        iss = "https://id.example.com",
        sub = "user-123",
        ["urn:zitadel:iam:user:resourceowner:id"] = "company-456",
        ["urn:zitadel:iam:user:resourceowner:name"] = "ACME Inc",
        ["urn:zitadel:iam:user:resourceowner:primary_domain"] = "acme.example.com",
        ["urn:zitadel:iam:org:project:abc:roles"] = {
            admin = {}
        }
    }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    for _, key in ipairs(remove or {}) do
        base[key] = nil
    end
    return base
end

local function mint(conf_overrides, claim_overrides)
    return ws_ticket.sign(conf(conf_overrides), access_token_claims(claim_overrides))
end

describe("ws_ticket.sign", function()

    it("produces a token Kong's own JWT parser accepts", function()
        local ticket, sign_err = mint()
        assert_truthy(ticket, "sign returned an error: " .. tostring(sign_err))

        local jwt, decode_err = jwt_parser:new(ticket)
        assert_falsy(decode_err, "decode error")
        assert_equal("HS256", jwt.header.alg)
        assert_equal("JWT", jwt.header.typ)
    end)

    it("signs with ws_ticket_secret", function()
        local jwt = jwt_parser:new(mint())
        assert_truthy(jwt:verify_signature(SECRET), "signature should verify with the configured secret")
    end)

    it("cannot be verified with any other secret", function()
        local jwt = jwt_parser:new(mint())
        assert_falsy(jwt:verify_signature("some-other-secret"), "signature must not verify with a foreign secret")
    end)

    it("carries the subject and the company id", function()
        local jwt = jwt_parser:new(mint())
        assert_equal("user-123", jwt.claims.sub)
        assert_equal("company-456", jwt.claims.cid)
    end)

    it("carries no roles, so it cannot widen authorisation", function()
        local jwt = jwt_parser:new(mint())
        for claim in pairs(jwt.claims) do
            assert_falsy(claim:find("roles", 1, true), "unexpected roles claim: " .. claim)
        end
    end)

    it("carries no company name or domain", function()
        local jwt = jwt_parser:new(mint())
        assert_falsy(jwt.claims["urn:zitadel:iam:user:resourceowner:name"])
        assert_falsy(jwt.claims["urn:zitadel:iam:user:resourceowner:primary_domain"])
    end)

    it("sets the configured issuer, which is what marks it as a ticket", function()
        local jwt = jwt_parser:new(mint({
            ws_ticket_issuer = "some-other-issuer"
        }))
        assert_equal("some-other-issuer", jwt.claims.iss)
    end)

    it("binds the configured audience", function()
        local jwt = jwt_parser:new(mint({
            ws_ticket_audience = "speech"
        }))
        assert_equal("speech", jwt.claims.aud)
    end)

    it("omits the audience when none is configured", function()
        local jwt = jwt_parser:new(mint({
            ws_ticket_audience = ""
        }))
        assert_falsy(jwt.claims.aud)
    end)

    it("expires ws_ticket_ttl seconds after issuance", function()
        local jwt = jwt_parser:new(mint({
            ws_ticket_ttl = 30
        }))
        assert_equal(30, jwt.claims.exp - jwt.claims.iat)
    end)

    it("backdates nbf so a fresh ticket survives replica clock skew", function()
        local jwt = jwt_parser:new(mint())
        assert_truthy(jwt.claims.nbf < jwt.claims.iat, "nbf should precede iat")

        local ok = jwt:verify_registered_claims({"exp", "nbf"})
        assert_truthy(ok, "a freshly minted ticket must pass its own claim checks")
    end)

    it("gives every ticket its own id", function()
        local first = jwt_parser:new(mint())
        local second = jwt_parser:new(mint())
        assert_truthy(first.claims.jti)
        assert_falsy(first.claims.jti == second.claims.jti, "jti should differ between tickets")
    end)

    it("refuses to sign an access token with no subject", function()
        local ticket, err = ws_ticket.sign(conf(), access_token_claims(nil, {"sub"}))
        assert_falsy(ticket)
        assert_contains("sub", err)
    end)

    it("refuses to sign an access token with no company id", function()
        local ticket, err = ws_ticket.sign(conf(), access_token_claims(nil,
            {"urn:zitadel:iam:user:resourceowner:id"}))
        assert_falsy(ticket)
        assert_contains("resourceowner", err)
    end)

    it("refuses to sign without a configured secret", function()
        local ticket, err = ws_ticket.sign(conf({
            ws_ticket_secret = ""
        }), access_token_claims())
        assert_falsy(ticket)
        assert_contains("ws_ticket_secret", err)
    end)

end)
