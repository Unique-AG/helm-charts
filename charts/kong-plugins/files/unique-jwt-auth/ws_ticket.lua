local cjson = require "cjson.safe"
local resty_sha256 = require "resty.sha256"
local to_hex = require "resty.string".to_hex
local openssl_rand = require "resty.openssl.rand"
local redis_store = require "kong.plugins.unique-jwt-auth.redis_store"

local _M = {}

local TICKET_BYTES = 32

local function sha256_hex(value)
  local sha = resty_sha256:new()
  sha:update(value)
  return to_hex(sha:final())
end

local function has_http_token(value, expected)
  if type(value) == "table" then
    for _, entry in ipairs(value) do
      if has_http_token(entry, expected) then
        return true
      end
    end
    return false
  end

  if type(value) ~= "string" then
    return false
  end

  for token in value:gmatch("[^,]+") do
    if token:match("^%s*(.-)%s*$"):lower() == expected then
      return true
    end
  end
  return false
end

local function origin_allowed(conf)
  if #conf.ticket_allowed_origins == 0 then
    return true
  end

  local origin = kong.request.get_header("origin")
  if type(origin) ~= "string" then
    return false
  end

  for _, allowed in ipairs(conf.ticket_allowed_origins) do
    if origin == allowed then
      return true
    end
  end
  return false
end

local function strip_ticket_from_query(conf)
  local args = kong.request.get_query()
  args[conf.ticket_param_name] = nil
  kong.service.request.set_query(args)
end

local function set_identity_headers(record)
  kong.service.request.set_header("x-user-id", record.user_id)
  kong.service.request.set_header("x-company-id", record.company_id)
  kong.service.request.clear_header("x-user-roles")
  kong.service.request.clear_header("x-company-name")
  kong.service.request.clear_header("x-company-domain")
end

function _M.is_mint_request(conf)
  return kong.request.get_method() == "POST"
    and kong.request.get_path() == conf.ticket_mint_path
end

function _M.get_ticket_from_request(conf)
  return kong.request.get_query()[conf.ticket_param_name]
end

function _M.validate_upgrade_request(conf)
  if not has_http_token(kong.request.get_header("upgrade"), "websocket")
    or not has_http_token(kong.request.get_header("connection"), "upgrade")
  then
    kong.log.warn("WebSocket ticket presented on a non-upgrade request")
    return false, {
      status = 401,
      message = "Unauthorized",
      warning_reason = "ws_ticket_unknown",
    }
  end

  if not origin_allowed(conf) then
    kong.log.warn("WebSocket ticket rejected because of its Origin")
    return false, {
      status = 401,
      message = "Unauthorized",
      warning_reason = "ws_ticket_origin_rejected",
    }
  end

  return true
end

function _M.create_ticket(conf)
  local user_id = kong.ctx.shared.user_id
  local company_id = kong.ctx.shared.company_id
  if not user_id or user_id == "" or not company_id or company_id == "" then
    kong.log.warn("WebSocket ticket mint rejected because identity is incomplete")
    return nil, {
      status = 401,
      message = "Unauthorized",
    }
  end

  local raw, random_err = openssl_rand.bytes(TICKET_BYTES)
  if not raw then
    kong.log.err("WebSocket ticket generation failed: ", random_err)
    return nil, {
      status = 500,
      message = "An unexpected error occurred",
    }
  end

  local ticket = ngx.encode_base64(raw, true):gsub("%+", "-"):gsub("/", "_")
  local record = cjson.encode({
    user_id = user_id,
    company_id = company_id,
  })
  local stored, store_err = redis_store.put(conf, sha256_hex(ticket), record)
  if not stored then
    kong.log.err("WebSocket ticket Redis write failed: ", store_err)
    return nil, {
      status = 503,
      message = "Service Unavailable",
      warning_reason = "ws_ticket_redis_error",
    }
  end

  return {
    ticket = ticket,
    expires_in = conf.ticket_ttl,
  }
end

function _M.do_authentication(conf, ticket)
  if type(ticket) ~= "string" or ticket == "" then
    return false, {
      status = 401,
      message = "Unauthorized",
      warning_reason = "ws_ticket_unknown",
    }
  end

  local raw, consume_err = redis_store.consume(conf, sha256_hex(ticket))
  if not raw then
    if consume_err ~= "not found" then
      kong.log.err("WebSocket ticket Redis read failed: ", consume_err)
      return false, {
        status = 503,
        message = "Service Unavailable",
        warning_reason = "ws_ticket_redis_error",
      }
    end

    kong.log.warn("Unknown, expired, or replayed WebSocket ticket")
    return false, {
      status = 401,
      message = "Unauthorized",
      warning_reason = "ws_ticket_unknown",
    }
  end

  local record = cjson.decode(raw)
  if type(record) ~= "table"
    or type(record.user_id) ~= "string"
    or record.user_id == ""
    or type(record.company_id) ~= "string"
    or record.company_id == ""
  then
    kong.log.warn("WebSocket ticket contained an invalid identity")
    return false, {
      status = 401,
      message = "Unauthorized",
      warning_reason = "ws_ticket_unknown",
    }
  end

  set_identity_headers(record)
  strip_ticket_from_query(conf)
  return true
end

return _M
