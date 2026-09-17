local constants = require "kong.constants"

local _M = {}

local function clear_header(name)
    kong.service.request.clear_header(name)
end

function _M.clear_headers()
    clear_header(constants.HEADERS.CONSUMER_ID)
    clear_header(constants.HEADERS.CONSUMER_CUSTOM_ID)
    clear_header(constants.HEADERS.CONSUMER_USERNAME)
    clear_header(constants.HEADERS.CREDENTIAL_IDENTIFIER)
    clear_header(constants.HEADERS.ANONYMOUS)
end

function _M.set(consumer, credential, token)
    kong.client.authenticate(consumer, credential)

    local set_header = kong.service.request.set_header

    _M.clear_headers()

    if consumer and consumer.id then
        set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
    end

    if consumer and consumer.custom_id then
        kong.log.debug("found consumer " .. consumer.custom_id)
        set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
    end

    if consumer and consumer.username then
        set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
    end

    if credential and credential.key then
        set_header(constants.HEADERS.CREDENTIAL_IDENTIFIER, credential.key)
    end

    if not credential then
        set_header(constants.HEADERS.ANONYMOUS, true)
    end

    kong.ctx.shared.authenticated_jwt_token = token
end

function _M.load_by_id(id)
    local cache_key = kong.db.consumers:cache_key(id)
    return kong.cache:get(
        cache_key,
        nil,
        kong.client.load_consumer,
        id,
        true
    )
end

return _M
