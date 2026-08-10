-------------------------------------------------------------------------------
-- Short-lived WebSocket upgrade tickets.
--
-- Browsers cannot set an Authorization header on a WebSocket handshake, so the
-- credential has to travel in the query string — where it ends up in gateway
-- access logs, browser history and Referer headers. Instead of putting the
-- Zitadel access token there, clients exchange it at the mint endpoint for one
-- of these tickets.
--
-- A ticket is an HS256 JWT that:
--   * lives for seconds rather than the access token's minutes or hours,
--   * carries only the identity the upstream services need (sub + company id),
--     never roles, so it cannot widen anyone's authorisation,
--   * is signed with a secret that never leaves the gateway, so it cannot be
--     minted by a client or replayed against the REST API.
--
-- The signing secret is symmetric on purpose: the same Kong deployment both
-- mints and verifies, and nothing downstream ever needs to check a ticket.
-------------------------------------------------------------------------------

local cjson = require "cjson.safe"
local hmac = require "resty.openssl.hmac"
local resty_random = require "resty.random"
local to_hex = require "resty.string".to_hex

local ALGORITHM = "HS256"
local ZITADEL_RESOURCE_OWNER_CLAIM = "urn:zitadel:iam:user:resourceowner:id"
-- Absorb small clock differences between gateway replicas, which would
-- otherwise make a freshly minted ticket fail its own nbf check.
local NBF_LEEWAY_SECONDS = 5
local JTI_BYTES = 16

local function base64url(input)
    return (ngx.encode_base64(input, true):gsub("%+", "-"):gsub("/", "_"))
end

local function encode_segment(value)
    local encoded, err = cjson.encode(value)
    if not encoded then
        return nil, err or "could not encode segment"
    end
    return base64url(encoded)
end

local function new_jti()
    local bytes = resty_random.bytes(JTI_BYTES)
    if not bytes then
        return nil, "could not generate ticket id"
    end
    return to_hex(bytes)
end

local _M = {
    ALGORITHM = ALGORITHM,
    ZITADEL_RESOURCE_OWNER_CLAIM = ZITADEL_RESOURCE_OWNER_CLAIM
}

-------------------------------------------------------------------------------
-- Return the name of the first identity claim a ticket needs that is missing
-- from the access-token claims, or nil when both are present.
--
-- Shared by the mint endpoint (so a client credential gap becomes a 401 rather
-- than a gateway 500) and by sign() itself, so the claim names live in one place.
-------------------------------------------------------------------------------
function _M.missing_identity_claim(claims)
    if type(claims) ~= "table" then
        return "sub"
    end
    if type(claims.sub) ~= "string" or claims.sub == "" then
        return "sub"
    end
    local company = claims[ZITADEL_RESOURCE_OWNER_CLAIM]
    if type(company) ~= "string" or company == "" then
        return ZITADEL_RESOURCE_OWNER_CLAIM
    end
    return nil
end

-------------------------------------------------------------------------------
-- Mint a ticket from the claims of an already-verified Zitadel access token.
--
-- @param conf   plugin configuration
-- @param claims claims of the verified access token
-- @return ticket string, or nil plus an error message
-------------------------------------------------------------------------------
function _M.sign(conf, claims)
    if type(conf.ws_ticket_secret) ~= "string" or conf.ws_ticket_secret == "" then
        return nil, "ws_ticket_secret is not configured"
    end

    -- Both are required: browser-bridge refuses any upgrade that does not carry
    -- gateway-stamped x-user-id and x-company-id headers.
    local missing = _M.missing_identity_claim(claims)
    if missing then
        return nil, "access token has no '" .. missing .. "' claim"
    end

    local subject = claims.sub
    local company = claims[ZITADEL_RESOURCE_OWNER_CLAIM]

    local jti, jti_err = new_jti()
    if not jti then
        return nil, jti_err
    end

    local now = ngx.time()
    local ticket_claims = {
        iss = conf.ws_ticket_issuer,
        sub = subject,
        cid = company,
        iat = now,
        nbf = now - NBF_LEEWAY_SECONDS,
        exp = now + conf.ws_ticket_ttl,
        jti = jti
    }

    if type(conf.ws_ticket_audience) == "string" and conf.ws_ticket_audience ~= "" then
        ticket_claims.aud = conf.ws_ticket_audience
    end

    local header_segment, header_err = encode_segment({
        typ = "JWT",
        alg = ALGORITHM
    })
    if not header_segment then
        return nil, header_err
    end

    local claims_segment, claims_err = encode_segment(ticket_claims)
    if not claims_segment then
        return nil, claims_err
    end

    local signing_input = header_segment .. "." .. claims_segment

    local mac, mac_err = hmac.new(conf.ws_ticket_secret, "sha256")
    if not mac then
        return nil, mac_err or "could not initialise hmac"
    end

    local updated, update_err = mac:update(signing_input)
    if not updated then
        return nil, update_err or "could not sign ticket"
    end

    local signature, final_err = mac:final()
    if not signature then
        return nil, final_err or "could not sign ticket"
    end

    return signing_input .. "." .. base64url(signature)
end

return _M
