local cjson = require "cjson.safe"
local bit = require "bit"
local resty_sha256 = require "resty.sha256"
local to_hex = require "resty.string".to_hex
local openssl_rand = require "resty.openssl.rand"
local openssl_hmac = require "resty.openssl.hmac"
local redis_store = require "kong.plugins.unique-jwt-auth.redis_store"

local _M = {}

local TICKET_BYTES = 32

local function sha256_hex(value)
  local sha = resty_sha256:new()
  sha:update(value)
  return to_hex(sha:final())
end

local function hmac_sha256_hex(secret, value)
  local hmac, hmac_err = openssl_hmac.new(secret, "sha256")
  if not hmac then
    return nil, hmac_err
  end

  local digest, digest_err = hmac:final(value)
  if not digest then
    return nil, digest_err
  end
  return to_hex(digest)
end

local function constant_time_equal(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then
    return false
  end

  local diff = bit.bxor(#a, #b)
  local max_len = math.max(#a, #b)
  for index = 1, max_len do
    local left = index <= #a and a:byte(index) or 0
    local right = index <= #b and b:byte(index) or 0
    diff = bit.bor(diff, bit.bxor(left, right))
  end
  return diff == 0
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

local function path_allowed(request_path, exact_paths, path_suffixes)
  for _, allowed in ipairs(exact_paths or {}) do
    if request_path == allowed then
      return true
    end
  end

  for _, suffix in ipairs(path_suffixes or {}) do
    if request_path:sub(-#suffix) == suffix then
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

local function unauthorized(reason, warning_reason)
  kong.log.warn(reason)
  return false, {
    status = 401,
    message = "Unauthorized",
    warning_reason = warning_reason,
  }
end

local function build_mac(conf, ticket_hash, record_json)
  return hmac_sha256_hex(
    conf.ticket_record_secret,
    ticket_hash .. "." .. record_json
  )
end

local function build_record_envelope(conf, ticket_hash, record)
  local record_json = cjson.encode(record)
  if not record_json then
    return nil, "record encode failed"
  end

  local mac, mac_err = build_mac(conf, ticket_hash, record_json)
  if not mac then
    return nil, "record MAC failed: " .. tostring(mac_err)
  end

  local envelope = cjson.encode({
    r = record_json,
    m = mac,
  })
  if not envelope then
    return nil, "record envelope encode failed"
  end

  return envelope
end

local function verify_record_envelope(conf, ticket_hash, raw)
  local envelope = cjson.decode(raw)
  if type(envelope) ~= "table"
    or type(envelope.r) ~= "string"
    or type(envelope.m) ~= "string"
  then
    return nil, "forged"
  end

  local expected_mac, mac_err = build_mac(conf, ticket_hash, envelope.r)
  if not expected_mac then
    kong.log.err("WebSocket ticket MAC verification failed: ", mac_err)
    return nil, "forged"
  end

  if not constant_time_equal(envelope.m, expected_mac) then
    return nil, "forged"
  end

  local record = cjson.decode(envelope.r)
  if type(record) ~= "table" then
    return nil, "forged"
  end

  if type(record.exp) ~= "number" or ngx.time() >= record.exp then
    return nil, "expired"
  end

  return record
end

function _M.is_mint_request(conf)
  return kong.request.get_method() == "POST"
    and path_allowed(
      kong.request.get_path(),
      conf.ticket_mint_paths,
      conf.ticket_mint_path_suffixes
    )
end

function _M.get_ticket_from_request(conf)
  return kong.request.get_query()[conf.ticket_param_name]
end

function _M.validate_upgrade_request(conf)
  if not path_allowed(
    kong.request.get_path(),
    conf.ticket_upgrade_paths,
    conf.ticket_upgrade_path_suffixes
  ) then
    kong.log.warn("WebSocket ticket presented on an unexpected path")
    return false, {
      status = 401,
      message = "Unauthorized",
      warning_reason = "ws_ticket_unknown",
    }
  end

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
  local ticket_hash = sha256_hex(ticket)
  local envelope, envelope_err = build_record_envelope(conf, ticket_hash, {
    user_id = user_id,
    company_id = company_id,
    exp = ngx.time() + conf.ticket_ttl,
  })
  if not envelope then
    kong.log.err("WebSocket ticket record signing failed: ", envelope_err)
    return nil, {
      status = 500,
      message = "An unexpected error occurred",
    }
  end

  local stored, store_err = redis_store.put(conf, ticket_hash, envelope)
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

  local ticket_hash = sha256_hex(ticket)
  local raw, consume_err = redis_store.consume(conf, ticket_hash)
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

  local record, record_err = verify_record_envelope(conf, ticket_hash, raw)
  if record_err == "forged" then
    return unauthorized(
      "WebSocket ticket contained a forged identity record",
      "ws_ticket_forged"
    )
  elseif record_err == "expired" then
    return unauthorized(
      "WebSocket ticket contained an expired identity record",
      "ws_ticket_expired"
    )
  end

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
