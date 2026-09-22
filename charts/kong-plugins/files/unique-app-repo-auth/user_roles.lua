-------------------------------------------------------------------------------
-- Formats the `roles` value from /api-keys/validate into the bare
-- comma-separated list that `unique-jwt-auth` stamps on `x-user-roles`.
--
-- The documented contract is a comma-separated string. Anything else is
-- rejected rather than coerced: `cjson.encode` used to wrap a string in quotes,
-- which corrupted the first and last role once downstream split on ",". Coercing
-- an unexpected shape trades that bug for a different one, so unusable payloads
-- fail closed and the caller leaves the header unset.
-------------------------------------------------------------------------------

local cjson = require("cjson.safe")

local type = type
local pairs = pairs
local concat = table.concat

local M = {}

-- Reasons a value could not be formatted. MISSING and EMPTY are ordinary (an
-- API key with no roles); UNEXPECTED means the response shape changed.
M.MISSING = "missing"
M.EMPTY = "empty"
M.UNEXPECTED = "unexpected"

-- Returns the formatted list, or nil plus a reason constant and a detail string
-- safe to log (shapes and types only, never role values).
function M.format(roles)
    -- cjson decodes JSON null to a truthy lightuserdata sentinel.
    if roles == nil or roles == cjson.null then
        return nil, M.MISSING, "no roles in response"
    end

    if type(roles) == "string" then
        if roles == "" then
            return nil, M.EMPTY, "empty roles string"
        end
        return roles
    end

    if type(roles) ~= "table" then
        return nil, M.UNEXPECTED, "roles is a " .. type(roles)
    end

    local keys = 0
    for _ in pairs(roles) do
        keys = keys + 1
    end

    if keys == 0 then
        return nil, M.EMPTY, "empty roles array"
    end

    -- A JSON object and a sparse array are both tables; concat would silently
    -- walk only the array part and drop the rest.
    if keys ~= #roles then
        return nil, M.UNEXPECTED, "roles is an object or a sparse array"
    end

    for index = 1, keys do
        local entry = roles[index]
        if type(entry) ~= "string" then
            return nil, M.UNEXPECTED, "roles[" .. index .. "] is a " .. type(entry)
        end
        if entry == "" then
            return nil, M.UNEXPECTED, "roles[" .. index .. "] is empty"
        end
        if entry:find(",", 1, true) then
            return nil, M.UNEXPECTED, "roles[" .. index .. "] contains a comma"
        end
    end

    return concat(roles, ",")
end

return M
