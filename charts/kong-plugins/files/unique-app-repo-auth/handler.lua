local constants = require "kong.constants"
local http = require("resty.http")
local cjson = require("cjson.safe")

local fmt = string.format
local kong = kong
local type = type
local error = error
local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local re_gmatch = ngx.re.gmatch

local priority_env_var = "UNIQUE_APP_REPO_AUTH_PRIORITY"
local priority
if os.getenv(priority_env_var) then
    priority = tonumber(os.getenv(priority_env_var))
else
    priority = 1004
end
kong.log.info('UNIQUE_APP_REPO_AUTH_PRIORITY: ' .. priority)

local UniqueAppRepoAuthHandler = {
    PRIORITY = priority,
    VERSION = "0.1.0"
}

--- Retrieve an auth token in a request.
-- Checks for the auth token in URI parameters, then in cookies, and finally
-- in the configured header_names (defaults to `[Authorization]`).
-- @param conf Plugin configuration
-- @return token auth token contained in request (can be a table) or nil
-- @return err
local function retrieve_tokens(conf)
    local token_set = {}
    local args = kong.request.get_query()
    for _, v in ipairs(conf.uri_param_names) do
        local token = args[v] -- can be a table
        if token then
            if type(token) == "table" then
                for _, t in ipairs(token) do
                    if t ~= "" then
                        token_set[t] = true
                    end
                end

            elseif token ~= "" then
                token_set[token] = true
            end
        end
    end

    local var = ngx.var
    for _, v in ipairs(conf.cookie_names) do
        local cookie = var["cookie_" .. v]
        if cookie and cookie ~= "" then
            token_set[cookie] = true
        end
    end

    local request_headers = kong.request.get_headers()
    for _, v in ipairs(conf.header_names) do
        local token_header = request_headers[v]
        if token_header then
            if type(token_header) == "table" then
                token_header = token_header[1]
            end
            local iterator, iter_err = re_gmatch(token_header, "\\s*[Bb]earer\\s+(.+)", "jo")
            if not iterator then
                kong.log.err(iter_err)
                break
            end

            local m, err = iterator()
            if err then
                kong.log.err(err)
                break
            end

            if m and #m > 0 then
                if m[1] ~= "" then
                    token_set[m[1]] = true
                end
            end
        end
    end

    local tokens_n = 0
    local tokens = {}
    for token, _ in pairs(token_set) do
        tokens_n = tokens_n + 1
        tokens[tokens_n] = token
    end

    if tokens_n == 0 then
        return nil
    end

    if tokens_n == 1 then
        return tokens[1]
    end

    return tokens
end

local function set_consumer(consumer, credential, token)
    kong.client.authenticate(consumer, credential)

    local set_header = kong.service.request.set_header
    local clear_header = kong.service.request.clear_header

    if consumer and consumer.id then
        set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
    else
        clear_header(constants.HEADERS.CONSUMER_ID)
    end

    if consumer and consumer.custom_id then
        kong.log.debug("found consumer " .. consumer.custom_id)
        set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
    else
        clear_header(constants.HEADERS.CONSUMER_CUSTOM_ID)
    end

    if consumer and consumer.username then
        set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
    else
        clear_header(constants.HEADERS.CONSUMER_USERNAME)
    end

    if credential and credential.key then
        set_header(constants.HEADERS.CREDENTIAL_IDENTIFIER, credential.key)
    else
        clear_header(constants.HEADERS.CREDENTIAL_IDENTIFIER)
    end

    if credential then
        clear_header(constants.HEADERS.ANONYMOUS)
    else
        set_header(constants.HEADERS.ANONYMOUS, true)
    end
end

local function set_anonymous_consumer(anonymous)
    local consumer_cache_key = kong.db.consumers:cache_key(anonymous)
    local consumer, err = kong.cache:get(consumer_cache_key, nil, kong.client.load_consumer, anonymous, true)
    if err then
        kong.log.err(err)
        return kong.response.exit(500, {
            message = "An unexpected error occurred during authentication"
        })
    end

    set_consumer(consumer)
end

local function validate_api_key(app_repository_url, app_id, company_id, token, user_id)
    local httpc = http.new()

    local path
    if user_id then
        path = string.format("/api-keys/validate?company-id=%s&app-id=%s&user-id=%s&api-key=%s",
            ngx.escape_uri(company_id), ngx.escape_uri(app_id), ngx.escape_uri(user_id), ngx.escape_uri(token))
    else
        path = string.format("/api-keys/validate?company-id=%s&app-id=%s&api-key=%s",
            ngx.escape_uri(company_id), ngx.escape_uri(app_id), ngx.escape_uri(token))
    end

    local res, err = httpc:request_uri(app_repository_url .. path, {
        method = "GET"
    })

    if err then
        kong.log.err("Failed to validate API key: ", err)
        return false
    end

    if res.status == 200 then
        return true
    else
        kong.log.warn("API key validation failed with status: ", res.status, " and body: ", res.body)
        return false
    end
end

local function do_authentication(conf)
    local token, err = retrieve_tokens(conf)
    if err then
        kong.log.err(err)
        return kong.response.exit(500, {
            message = "An unexpected error occurred"
        })
    end

    local token_type = type(token)
    if token_type ~= "string" then
        if token_type == "nil" then
            return false, {
                status = 401,
                message = "Unauthorized"
            }
        elseif token_type == "table" then
            return false, {
                status = 401,
                message = "Multiple tokens provided"
            }
        else
            return false, {
                status = 401,
                message = "Unrecognizable token"
            }
        end
    end

    local request_headers = kong.request.get_headers()
    local app_id = request_headers["x-app-id"]
    local company_id = request_headers["x-company-id"]
    local user_id = request_headers["x-user-id"]

    if not app_id or not company_id then
        return false, {
            status = 401,
            message = "Missing app_id or company_id"
        }
    end

    kong.log.info("app_repository_url: " .. conf.app_repository_url .. " app_id: " .. app_id .. " company_id: " .. company_id .. " user_id: " .. user_id)

    if validate_api_key(conf.app_repository_url, app_id, company_id, token, user_id) then
        return true
    end

    -- TODO: add consumer matching

    return false, {
        status = 401,
        message = "Unauthorized"
    }
end

--- When conf.anonymous is enabled we are in "logical OR" authentication flow.
--- Meaning - either anonymous consumer is enabled or there are multiple auth plugins
--- and we need to passthrough on failed authentication.
local function logical_OR_authentication(conf)
    if kong.client.get_credential() then
        -- we're already authenticated and in "logical OR" between auth methods -- early exit
        return
    end

    local ok, _ = do_authentication(conf)
    if not ok then
        set_anonymous_consumer(conf.anonymous)
    end
end

--- When conf.anonymous is not set we are in "logical AND" authentication flow.
--- Meaning - if this authentication fails the request should not be authorized
--- even though other auth plugins might have successfully authorized user.
local function logical_AND_authentication(conf)
    local ok, err = do_authentication(conf)
    if not ok then
        return kong.response.exit(err.status, err.errors or {
            message = err.message
        }, err.headers)
    end
end

function UniqueAppRepoAuthHandler:access(conf)
    kong.log.info("UniqueAppRepoAuthHandler:access")
    -- check if preflight request and whether it should be authenticated
    if not conf.run_on_preflight and kong.request.get_method() == "OPTIONS" then
        return
    end

    if conf.anonymous then
        return logical_OR_authentication(conf)
    else
        return logical_AND_authentication(conf)
    end
end

return UniqueAppRepoAuthHandler
