local http = require("resty.http")
local cjson = require("cjson.safe")
local convert = require "kong.plugins.unique-jwt-auth.key_conversion"

local function get_wellknown_endpoint(well_known_template, issuer)
    return string.format(well_known_template, issuer)
end

local function get_issuer_keys(well_known_endpoint, conf)
    local httpc = http.new()
    local jwks_uri = conf.jwks_uri

    if not jwks_uri then
        local res, err = httpc:request_uri(well_known_endpoint, {
            method = "GET",
            headers = conf.well_known_extra_headers or {},
            ssl_verify = conf.ssl_verify
        })
        if err then
            return nil, err
        end

        local body_table, err = cjson.decode(res.body)
        if err then
            return nil, err
        end

        jwks_uri = body_table['jwks_uri']
        if type(jwks_uri) ~= "string" then
            return nil, "Invalid or missing jwks_uri in well-known response"
        end
        if conf.ssl_verify and jwks_uri:sub(1, 8) ~= "https://" then
            return nil, "jwks_uri must use HTTPS when ssl_verify is enabled"
        end
    end

    local res, err = httpc:request_uri(jwks_uri, {
        method = "GET",
        headers = conf.jwks_extra_headers or {},
        ssl_verify = conf.ssl_verify
    })
    if err then
        return nil, err
    end

    local body_table, err = cjson.decode(res.body)
    if err then
        return nil, err
    end

    local keys = {}
    for _, key in ipairs(body_table['keys']) do
        local pem, err = convert.convert_kc_key(key)
        if pem then
            pem = pem:gsub("[\r\n%s]+", "")
            pem = "-----BEGIN PUBLIC KEY-----\n" .. pem .. "\n-----END PUBLIC KEY-----"
            keys[#keys + 1] = pem
        end
    end
    if #keys == 0 then
        return nil, "No usable RSA keys found in JWKS"
    end
    return keys, nil
end

return {
    get_wellknown_endpoint = get_wellknown_endpoint,
    get_issuer_keys = get_issuer_keys
}
