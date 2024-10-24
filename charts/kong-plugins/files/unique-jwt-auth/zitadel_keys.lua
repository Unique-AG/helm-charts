local http = require("resty.http")
local cjson = require("cjson.safe")
local convert = require "kong.plugins.unique-jwt-auth.key_conversion"

local function get_wellknown_endpoint(well_known_template, issuer)
    return string.format(well_known_template, issuer)
end

local function get_issuer_keys(well_known_endpoint)
    local httpc = http.new()

    local res, err = httpc:request_uri(well_known_endpoint, {
        method = "GET"
    })
    if err then
        return nil, err
    end

    local body_table, err = cjson.decode(res.body)
    if err then
        return nil, err
    end

    local res, err = httpc:request_uri(body_table['jwks_uri'], {
        method = "GET"
    })
    if err then
        return nil, err
    end

    local body_table, err = cjson.decode(res.body)
    if err then
        return nil, err
    end

    local keys = {}
    for i, key in ipairs(body_table['keys']) do
        keys[i] = convert.convert_kc_key(key)

        -- Remove any newlines and spaces
        keys[i] = keys[i]:gsub("[\r\n%s]+", "")

        -- Add header and footer
        keys[i] = "-----BEGIN PUBLIC KEY-----\n" .. keys[i] .. "\n-----END PUBLIC KEY-----"
    end
    return keys, nil
end

return {
    get_wellknown_endpoint = get_wellknown_endpoint,
    get_issuer_keys = get_issuer_keys
}
