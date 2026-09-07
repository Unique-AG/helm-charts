local redis = require "resty.redis"

local _M = {}

local function is_present(value)
  return value and value ~= "" and value ~= ngx.null
end

local function close(red)
  local ok, err = red:close()
  if not ok then
    kong.log.warn("Redis connection close failed: ", err)
  end
end

local function connect(conf)
  local red = redis:new()
  red:set_timeout(conf.redis_timeout)

  local options = {
    pool = table.concat({
      conf.redis_host,
      tostring(conf.redis_port),
      tostring(conf.redis_database),
      tostring(conf.redis_ssl),
      is_present(conf.redis_server_name) and conf.redis_server_name or "",
      is_present(conf.redis_username) and conf.redis_username or "",
    }, ":"),
    ssl = conf.redis_ssl,
    ssl_verify = conf.redis_ssl_verify,
    server_name = conf.redis_server_name,
  }
  local ok, err = red:connect(conf.redis_host, conf.redis_port, options)
  if not ok then
    return nil, "connect failed: " .. tostring(err)
  end

  local reused, reused_err = red:get_reused_times()
  if reused == nil then
    close(red)
    return nil, "connection reuse check failed: " .. tostring(reused_err)
  end

  if reused == 0 then
    if is_present(conf.redis_password) then
      local authenticated, auth_err
      if is_present(conf.redis_username) then
        authenticated, auth_err = red:auth(
          conf.redis_username,
          conf.redis_password
        )
      else
        authenticated, auth_err = red:auth(conf.redis_password)
      end
      if not authenticated then
        close(red)
        return nil, "authentication failed: " .. tostring(auth_err)
      end
    end

    if conf.redis_database ~= 0 then
      local selected, select_err = red:select(conf.redis_database)
      if not selected then
        close(red)
        return nil, "database selection failed: " .. tostring(select_err)
      end
    end
  end

  return red
end

local function keepalive(red)
  local ok, err = red:set_keepalive(10000, 100)
  if not ok then
    kong.log.warn("Redis keepalive failed: ", err)
    close(red)
  end
end

local function key(conf, ticket_hash)
  return conf.redis_key_prefix .. ticket_hash
end

function _M.put(conf, ticket_hash, value)
  local red, err = connect(conf)
  if not red then
    return nil, err
  end

  local result, set_err = red:set(
    key(conf, ticket_hash),
    value,
    "EX",
    conf.ticket_ttl,
    "NX"
  )
  if set_err then
    close(red)
    return nil, "SET failed: " .. tostring(set_err)
  end
  keepalive(red)
  if result ~= "OK" then
    return nil, "SET NX conflict"
  end
  return true
end

function _M.consume(conf, ticket_hash)
  local red, err = connect(conf)
  if not red then
    return nil, err
  end

  local result, get_err = red:getdel(key(conf, ticket_hash))
  if get_err then
    close(red)
    return nil, "GETDEL failed: " .. tostring(get_err)
  end
  keepalive(red)
  if result == nil or result == ngx.null then
    return nil, "not found"
  end
  return result
end

return _M
