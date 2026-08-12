-------------------------------------------------------------------------------
-- Builds JWTs for the handler specs.
--
-- Independent of ws_ticket.lua so specs can forge expired, mismatched, or
-- otherwise invalid tokens the minter would never emit.
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
