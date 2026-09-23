local cjson = require "cjson.safe"
local bit = require "bit"
local resty_sha256 = require "resty.sha256"
local to_hex = require "resty.string".to_hex
local openssl_rand = require "resty.openssl.rand"
local openssl_hmac = require "resty.openssl.hmac"
local consumer_context = require "kong.plugins.unique-jwt-auth.consumer_context"
local redis_store = require "kong.plugins.unique-jwt-auth.redis_store"

local _M = {}

local TICKET_BYTES = 32

local function log_ticket_event(conf, message)
  if conf.ticket_debug_logging then
    kong.log.info("ws_ticket ", message)
  end
end

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
  local clear_header = kong.service.request.clear_header
  local set_header = kong.service.request.set_header

  clear_header("x-user-id")
  clear_header("x-company-id")
  clear_header("x-user-roles")
  clear_header("x-company-name")
  clear_header("x-company-domain")

  set_header("x-user-id", record.user_id)
  set_header("x-company-id", record.company_id)

  if record.company_name then
    set_header("x-company-name", record.company_name)
  end
  if record.company_domain then
    set_header("x-company-domain", record.company_domain)
  end
  if record.user_roles and #record.user_roles > 0 then
    set_header("x-user-roles", table.concat(record.user_roles, ","))
  end
end

local function valid_optional_string(value)
  return value == nil or (type(value) == "string" and value ~= "")
end

local function valid_user_roles(roles)
  if roles == nil then
    return true
  end
  if type(roles) ~= "table" then
    return false
  end

  local count = 0
  for index, role in pairs(roles) do
    count = count + 1
    if type(index) ~= "number"
      or index < 1
      or index % 1 ~= 0
      or type(role) ~= "string"
      or role == ""
    then
      return false
    end
  end

  return count == #roles
end

local function valid_identity_record(record)
  return type(record) == "table"
    and type(record.user_id) == "string"
    and record.user_id ~= ""
    and type(record.company_id) == "string"
    and record.company_id ~= ""
    and valid_optional_string(record.company_name)
    and valid_optional_string(record.company_domain)
    and valid_optional_string(record.consumer_id)
    and valid_user_roles(record.user_roles)
end

local function copy_optional_string(record, name, value)
  if type(value) == "string" and value ~= "" then
    record[name] = value
  end
end

local function log_identity_presence(conf, identity, stage)
  if type(identity.user_id) == "string" and identity.user_id ~= "" then
    log_ticket_event(conf, stage .. " user_id found")
  end
  if type(identity.company_id) == "string" and identity.company_id ~= "" then
    log_ticket_event(conf, stage .. " company_id found")
  end
  if type(identity.company_name) == "string"
    and identity.company_name ~= ""
  then
    log_ticket_event(conf, stage .. " company_name found")
  end
  if type(identity.company_domain) == "string"
    and identity.company_domain ~= ""
  then
    log_ticket_event(conf, stage .. " company_domain found")
  end
  if type(identity.user_roles) == "table" and #identity.user_roles > 0 then
    log_ticket_event(conf, stage .. " user_roles found")
  end
  if type(identity.consumer_id) == "string"
    and identity.consumer_id ~= ""
  then
    log_ticket_event(conf, stage .. " consumer found")
  end
end

local function build_identity_record(conf)
  local shared = kong.ctx.shared
  local record = {
    user_id = shared.user_id,
    company_id = shared.company_id,
  }

  copy_optional_string(record, "company_name", shared.company_name)
  copy_optional_string(record, "company_domain", shared.company_domain)
  copy_optional_string(record, "consumer_id", shared.consumer_id)

  if type(shared.user_roles) == "table" and #shared.user_roles > 0 then
    record.user_roles = shared.user_roles
  end

  log_identity_presence(conf, record, "mint")
  return record
end

local function load_recorded_consumer(conf, record)
  if not record.consumer_id then
    return nil
  end
  if not conf.consumer_match then
    return nil, "ticket contains consumer identity while consumer matching is disabled"
  end

  local consumer, err = consumer_context.load_by_id(record.consumer_id)
  if err then
    return nil, "consumer lookup failed: " .. tostring(err)
  end
  if not consumer then
    return nil, "consumer no longer exists"
  end

  return consumer
end

local function apply_authentication(conf, record, consumer)
  set_identity_headers(record)
  log_ticket_event(conf, "identity headers restored")
  if consumer then
    consumer_context.set(consumer, nil, nil)
    log_ticket_event(conf, "consumer context restored")
  else
    consumer_context.clear_headers()
  end
end

local function invalid_identity_error()
  kong.log.warn("WebSocket ticket contained an invalid identity")
  return false, {
    status = 401,
    message = "Unauthorized",
    warning_reason = "ws_ticket_unknown",
  }
end

local function consumer_error(err)
  kong.log.warn("WebSocket ticket consumer rejected: ", err)
  return false, {
    status = 401,
    message = "Unauthorized",
    warning_reason = "ws_ticket_unknown",
  }
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
  local identity = build_identity_record(conf)
  if not valid_identity_record(identity) then
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
  log_ticket_event(conf, "ticket generated")
  local ticket_hash = sha256_hex(ticket)
  identity.exp = ngx.time() + conf.ticket_ttl
  local envelope, envelope_err = build_record_envelope(
    conf,
    ticket_hash,
    identity
  )
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
  log_ticket_event(conf, "ticket stored")

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
  log_ticket_event(conf, "ticket record retrieved")

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

  if not valid_identity_record(record) then
    return invalid_identity_error()
  end
  log_ticket_event(conf, "ticket record validated")
  log_identity_presence(conf, record, "consume")

  local consumer, lookup_err = load_recorded_consumer(conf, record)
  if lookup_err then
    return consumer_error(lookup_err)
  end
  if consumer then
    log_ticket_event(conf, "recorded consumer found")
  end

  apply_authentication(conf, record, consumer)
  strip_ticket_from_query(conf)
  log_ticket_event(conf, "ticket query removed")
  return true
end

return _M
