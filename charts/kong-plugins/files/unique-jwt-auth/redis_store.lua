-- Shared Redis helpers for single-use WebSocket tickets.
-- Connection pattern follows Kong's rate-limiting plugin: resty.redis per
-- request, AUTH/SELECT only on a fresh socket, keepalive pool keyed by
-- host:port:database so SELECT'd connections are never mixed.

local redis = require "resty.redis"

local _M = {}

-- Scope is checked inside the script so a ticket presented with the wrong
-- scope is rejected WITHOUT being deleted: a misrouted client must not burn
-- a ticket that is still valid for its intended socket. The sentinel cannot
-- collide with a stored record because records are always JSON objects.
local CONSUME_SCRIPT = [[
local v = redis.call('GET', KEYS[1])
if not v then
  return nil
end
local ok, rec = pcall(cjson.decode, v)
if ok and type(rec) == 'table' and rec.scope ~= ARGV[1] then
  return 'SCOPE_MISMATCH'
end
redis.call('DEL', KEYS[1])
return v
]]

-- INCR and EXPIRE must be one atomic unit: a failure between the two would
-- leave a counter without a TTL that never resets, permanently rate-limiting
-- that subject/IP until the key is deleted by hand.
local INCR_SCRIPT = [[
local c = redis.call('INCR', KEYS[1])
if c == 1 then
  redis.call('EXPIRE', KEYS[1], ARGV[1])
end
return c
]]

local function pool_name(conf)
  local db = conf.redis_database or 7
  return conf.redis_host .. ":" .. tostring(conf.redis_port) .. ":" .. tostring(db)
end

local function connect(conf)
  local red = redis:new()
  red:set_timeout(conf.redis_timeout_ms or 2000)

  local ok, err
  if conf.redis_ssl then
    ok, err = red:connect(conf.redis_host, conf.redis_port, {
      ssl = true,
      ssl_verify = conf.redis_ssl_verify and true or false,
      pool = pool_name(conf),
    })
  else
    ok, err = red:connect(conf.redis_host, conf.redis_port, {
      pool = pool_name(conf),
    })
  end
  if not ok then
    return nil, "redis connect failed: " .. tostring(err)
  end

  local reused = red:get_reused_times()
  if reused == 0 then
    if conf.redis_password and conf.redis_password ~= "" then
      local res, aerr = red:auth(conf.redis_password)
      if not res then
        red:close()
        return nil, "redis auth failed: " .. tostring(aerr)
      end
    end

    local db = conf.redis_database or 7
    if db ~= 0 then
      local res, serr = red:select(db)
      if not res then
        red:close()
        return nil, "redis select failed: " .. tostring(serr)
      end
    end
  end

  return red
end

local function keepalive(red)
  -- 10k idle pool, 60s idle timeout — same ballpark as Kong's own plugins
  local ok, err = red:set_keepalive(60000, 100)
  if not ok then
    kong.log.warn("redis set_keepalive failed: ", err)
    red:close()
  end
end

local function prefixed(conf, key)
  local prefix = conf.redis_key_prefix or "ws_ticket:"
  return prefix .. key
end

--- Store a ticket record. Fails if the key already exists (SET NX).
-- @return true on success, nil + err otherwise
function _M.put(conf, key, value, ttl)
  local red, err = connect(conf)
  if not red then
    return nil, err
  end

  local res, serr = red:set(prefixed(conf, key), value, "EX", ttl, "NX")
  keepalive(red)

  if serr then
    return nil, "redis SET failed: " .. tostring(serr)
  end
  if res ~= "OK" then
    return nil, "redis SET NX conflict"
  end
  return true
end

--- Atomically retrieve and delete a ticket record (EVAL GET+scope check+DEL).
-- A wrong-scope attempt leaves the record in place.
-- @return record string, or nil + err ("not found" / "scope mismatch" / redis error)
function _M.consume(conf, key, scope)
  local red, err = connect(conf)
  if not red then
    return nil, err
  end

  local res, serr = red:eval(CONSUME_SCRIPT, 1, prefixed(conf, key), scope or "")
  keepalive(red)

  if serr then
    return nil, "redis EVAL failed: " .. tostring(serr)
  end
  if res == ngx.null or res == nil then
    return nil, "not found"
  end
  if res == "SCOPE_MISMATCH" then
    return nil, "scope mismatch"
  end
  return res
end

--- Increment a counter with a sliding window TTL. Returns the new count.
-- Atomic EVAL so the counter can never exist without a TTL.
function _M.incr_with_expiry(conf, key, window)
  local red, err = connect(conf)
  if not red then
    return nil, err
  end

  local count, ierr = red:eval(INCR_SCRIPT, 1, prefixed(conf, key), window)
  keepalive(red)

  if not count or count == ngx.null then
    return nil, "redis INCR failed: " .. tostring(ierr)
  end
  return count
end

return _M
