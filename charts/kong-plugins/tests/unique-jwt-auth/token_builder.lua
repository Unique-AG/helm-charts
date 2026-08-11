-------------------------------------------------------------------------------
-- Builds JWTs for the handler specs.
--
-- Deliberately independent of ws_ticket.lua: the handler specs assert what the
-- plugin accepts, so they must be able to produce tokens the minter would
-- never emit — expired ones, forged ones, ones with a mismatched algorithm
-- header. Using the minter here would also make a bug that affects both sides
-- equally invisible.
-------------------------------------------------------------------------------

local cjson = require "cjson.safe"
local hmac = require "resty.openssl.hmac"

local M = {}

local function base64url(input)
    return (ngx.encode_base64(input, true):gsub("%+", "-"):gsub("/", "_"))
end

--- Assemble a JWT from an explicit header and claim set, HMAC-signed.
function M.build(header, claims, secret)
    local signing_input = base64url(cjson.encode(header)) .. "." .. base64url(cjson.encode(claims))

    local mac = assert(hmac.new(secret, "sha256"))
    assert(mac:update(signing_input))
    local signature = assert(mac:final())

    return signing_input .. "." .. base64url(signature)
end

return M
