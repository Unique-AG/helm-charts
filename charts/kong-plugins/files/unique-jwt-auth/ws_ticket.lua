-- Mint and consume single-use opaque WebSocket upgrade tickets.
-- Tickets are random opaque values (not JWTs). Only the SHA-256 hash is
-- stored in Redis together with identity, scope, and issuance time.

local cjson = require "cjson.safe"
local resty_sha256 = require "resty.sha256"
local to_hex = require "resty.string".to_hex
local openssl_rand = require "resty.openssl.rand"
local redis_store = require "kong.plugins.unique-jwt-auth.redis_store"

local encode_base64 = ngx.encode_base64

local _M = {}

local TICKET_BYTES = 32 -- 256 bits
local RATE_WINDOW_S = 60

local function b64url(raw)
  local b64 = encode_base64(raw, true) -- no_padding
  return (b64:gsub("+", "-"):gsub("/", "_"))
end

local function sha256_hex(value)
  local sha = resty_sha256:new()
  sha:update(value)
  return to_hex(sha:final())
end

local function ticket_key(hash)
  return "t:" .. hash
end

local function mint_rate_key(sub)
  return "mint:" .. sub
end

local function fail_rate_key(ip)
  return "fail:" .. (ip or "unknown")
end

--- Extract a Bearer token from Authorization (header only — never query/cookie).
function _M.bearer_from_authorization()
  local header = kong.request.get_header("authorization")
  if not header or header == "" then
    return nil
  end
  if type(header) == "table" then
    header = header[1]
  end
  local m = ngx.re.match(header, [[^\s*[Bb]earer\s+(.+)$]], "jo")
  if not m or not m[1] or m[1] == "" then
    return nil
  end
  return m[1]
end

--- True when the request is a genuine WebSocket upgrade.
function _M.is_websocket_upgrade()
  local upgrade = kong.request.get_header("upgrade")
  if not upgrade then
    return false
  end
  if type(upgrade) == "table" then
    upgrade = upgrade[1]
  end
  if not ngx.re.find(upgrade, [[websocket]], "ijo") then
    return false
  end

  local connection = kong.request.get_header("connection")
  if not connection then
    return false
  end
  if type(connection) == "table" then
    connection = connection[1]
  end
  return ngx.re.find(connection, [[upgrade]], "ijo") and true or false
end

--- Exact-match Origin against the configured allowlist.
-- When the allowlist is empty/nil, Origin is not enforced.
-- @return true, or false + reason
function _M.origin_allowed(conf)
  local allowed = conf.ticket_allowed_origins
  if not allowed or #allowed == 0 then
    return true
  end

  local origin = kong.request.get_header("origin")
  if not origin or origin == "" then
    return false, "missing"
  end
  if type(origin) == "table" then
    origin = origin[1]
  end

  for _, entry in ipairs(allowed) do
    if origin == entry then
      return true
    end
  end
  return false, "mismatch"
end

--- Read the ticket query parameter (never logged by callers).
function _M.ticket_from_query(conf)
  local name = conf.ticket_param_name or "ticket"
  local args = kong.request.get_query()
  local value = args[name]
  if not value or value == "" then
    return nil
  end
  if type(value) == "table" then
    value = value[1]
  end
  if not value or value == "" then
    return nil
  end
  return value
end

--- Strip the ticket query parameter before proxying upstream.
function _M.strip_ticket_from_query(conf)
  local name = conf.ticket_param_name or "ticket"
  local args = kong.request.get_query()
  if args[name] == nil then
    return
  end
  args[name] = nil
  kong.service.request.set_query(args)
end

local function missing_identity(claims)
  if not claims.sub or claims.sub == "" then
    return "sub"
  end
  local cid = claims["urn:zitadel:iam:user:resourceowner:id"]
  if not cid or cid == "" then
    return "urn:zitadel:iam:user:resourceowner:id"
  end
  return nil
end

--- Mint a single-use ticket for the verified JWT claims.
-- @return ticket, expires_in on success; nil, err_table on failure
--   err_table = { status, message, reason?, redis_error? }
function _M.mint(conf, claims)
  local missing = missing_identity(claims)
  if missing then
    return nil, {
      status = 401,
      message = "Unauthorized",
      reason = "ws_ticket_mint_missing_claims",
      claim = missing,
    }
  end

  local sub = claims.sub
  local company_id = claims["urn:zitadel:iam:user:resourceowner:id"]
  local ttl = conf.ticket_ttl or 20
  local scope = conf.ticket_scope
  if not scope or scope == "" then
    return nil, {
      status = 500,
      message = "An unexpected error occurred",
      reason = "ws_ticket_misconfigured",
    }
  end

  local limit = conf.ticket_mint_rate_limit
  if limit and limit > 0 then
    local count, rerr = redis_store.incr_with_expiry(conf, mint_rate_key(sub), RATE_WINDOW_S)
    if not count then
      return nil, {
        status = 503,
        message = "Service Unavailable",
        reason = "ws_ticket_redis_error",
        redis_error = rerr,
      }
    end
    if count > limit then
      return nil, {
        status = 429,
        message = "Too Many Requests",
        reason = "ws_ticket_mint_rate_limited",
      }
    end
  end

  local raw, rerr = openssl_rand.bytes(TICKET_BYTES)
  if not raw then
    return nil, {
      status = 500,
      message = "An unexpected error occurred",
      reason = "ws_ticket_rng_failed",
      redis_error = rerr,
    }
  end

  local ticket = b64url(raw)
  local hash = sha256_hex(ticket)
  local record = cjson.encode({
    sub = sub,
    company_id = company_id,
    scope = scope,
    iat = ngx.time(),
  })
  if not record then
    return nil, {
      status = 500,
      message = "An unexpected error occurred",
      reason = "ws_ticket_encode_failed",
    }
  end

  local ok, serr = redis_store.put(conf, ticket_key(hash), record, ttl)
  if not ok then
    return nil, {
      status = 503,
      message = "Service Unavailable",
      reason = "ws_ticket_redis_error",
      redis_error = serr,
    }
  end

  return ticket, ttl
end

--- Consume a ticket: atomic retrieve-and-delete, validate scope.
-- @return record table on success; nil, err_table on failure
function _M.consume(conf, ticket)
  if not ticket or ticket == "" then
    return nil, {
      status = 401,
      message = "Unauthorized",
      reason = "ws_ticket_unknown",
    }
  end

  local hash = sha256_hex(ticket)
  -- Scope is enforced inside the atomic consume script: a wrong-scope attempt
  -- is rejected without deleting the record, so a misrouted client does not
  -- burn a ticket that is still valid for its intended socket.
  local raw, err = redis_store.consume(conf, ticket_key(hash), conf.ticket_scope or "")
  if not raw then
    if err == "not found" then
      return nil, {
        status = 401,
        message = "Unauthorized",
        reason = "ws_ticket_unknown",
      }
    end
    if err == "scope mismatch" then
      return nil, {
        status = 401,
        message = "Unauthorized",
        reason = "ws_ticket_scope_mismatch",
      }
    end
    return nil, {
      status = 503,
      message = "Service Unavailable",
      reason = "ws_ticket_redis_error",
      redis_error = err,
    }
  end

  local record, derr = cjson.decode(raw)
  if not record or type(record) ~= "table" then
    return nil, {
      status = 401,
      message = "Unauthorized",
      reason = "ws_ticket_unknown",
      redis_error = derr,
    }
  end

  if not record.sub or record.sub == "" or not record.company_id or record.company_id == "" then
    return nil, {
      status = 401,
      message = "Unauthorized",
      reason = "ws_ticket_unknown",
    }
  end

  return record
end

--- Rate-limit failed consumptions per client IP. Returns true if limited.
function _M.fail_rate_limited(conf)
  local limit = conf.ticket_fail_rate_limit
  if not limit or limit <= 0 then
    return false
  end

  local ip = kong.client.get_forwarded_ip() or "unknown"
  local count, err = redis_store.incr_with_expiry(conf, fail_rate_key(ip), RATE_WINDOW_S)
  if not count then
    -- fail closed on Redis errors during rate limiting too
    kong.log.err("ticket fail-rate Redis error: ", err)
    return true, "ws_ticket_redis_error"
  end
  if count > limit then
    return true, "ws_ticket_fail_rate_limited"
  end
  return false
end

--- Stamp identity headers a ticket can vouch for; clear the rest.
function _M.set_identity_headers(record)
  local set_header = kong.service.request.set_header
  local clear_header = kong.service.request.clear_header

  set_header("x-user-id", record.sub)
  set_header("x-company-id", record.company_id)
  clear_header("x-user-roles")
  clear_header("x-company-name")
  clear_header("x-company-domain")
end

-- Exported for tests
_M._sha256_hex = sha256_hex
_M._ticket_key = ticket_key
_M._missing_identity = missing_identity

return _M
