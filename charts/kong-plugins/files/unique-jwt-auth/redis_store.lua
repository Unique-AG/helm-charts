local redis = require "resty.redis"

local _M = {}

local CLUSTER_LOCK_DICT = "redis_cluster_slot_locks"
local KEEPALIVE_TIMEOUT = 10000
local KEEPALIVE_CONNECTIONS = 100

local rediscluster

local function log_ticket_event(conf, message)
  if conf.ticket_debug_logging then
    kong.log.info("ws_ticket ", message)
  end
end

local function is_present(value)
  return value and value ~= "" and value ~= ngx.null
end

local function describe_error(err)
  if type(err) ~= "table" then
    return tostring(err)
  end

  local parts = {}
  for _, value in ipairs(err) do
    parts[#parts + 1] = describe_error(value)
  end
  if #parts == 0 then
    for name, value in pairs(err) do
      parts[#parts + 1] = tostring(name) .. ": " .. describe_error(value)
    end
  end
  return table.concat(parts, "; ")
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
  local ok, err = red:set_keepalive(
    KEEPALIVE_TIMEOUT,
    KEEPALIVE_CONNECTIONS
  )
  if not ok then
    kong.log.warn("Redis keepalive failed: ", err)
    close(red)
  end
end

local function key(conf, ticket_hash)
  return conf.redis_key_prefix .. ticket_hash
end

local function build_cluster_config(conf)
  local nodes = {}
  for _, node in ipairs(conf.redis_cluster_nodes or {}) do
    nodes[#nodes + 1] = {
      ip = node.host,
      port = node.port,
    }
  end

  local cluster_conf = {
    name = conf.redis_cluster_name,
    serv_list = nodes,
    connect_timeout = conf.redis_timeout,
    read_timeout = conf.redis_timeout,
    send_timeout = conf.redis_timeout,
    keepalive_timeout = KEEPALIVE_TIMEOUT,
    keepalive_cons = KEEPALIVE_CONNECTIONS,
    dict_name = CLUSTER_LOCK_DICT,
    lock_timeout = conf.redis_timeout / 1000,
    connect_opts = {
      ssl = conf.redis_ssl,
      ssl_verify = conf.redis_ssl_verify,
      server_name = is_present(conf.redis_server_name)
        and conf.redis_server_name or nil,
    },
  }

  if is_present(conf.redis_password) then
    cluster_conf.password = conf.redis_password
    if is_present(conf.redis_username) then
      cluster_conf.username = conf.redis_username
    end
  end

  return cluster_conf
end

local function new_cluster_client(conf)
  if not ngx.shared[CLUSTER_LOCK_DICT] then
    return nil, "Redis Cluster shared dictionary '" ..
      CLUSTER_LOCK_DICT .. "' is not configured"
  end

  if not rediscluster then
    local loaded, module_or_err = pcall(
      require,
      "kong.plugins.unique-jwt-auth.rediscluster"
    )
    if not loaded then
      return nil, "cluster client load failed: " .. tostring(module_or_err)
    end
    rediscluster = module_or_err
  end

  local cluster_conf = build_cluster_config(conf)
  local red, err = rediscluster:new(cluster_conf)
  if not red then
    return nil, "cluster client initialization failed: " ..
      describe_error(err)
  end
  return red
end

local function put_single(conf, ticket_hash, value)
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

local function put_cluster(conf, ticket_hash, value)
  local red, err = new_cluster_client(conf)
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
    return nil, "cluster SET failed: " .. describe_error(set_err)
  end
  if result ~= "OK" then
    return nil, "SET NX conflict"
  end
  return true
end

local function consume_single(conf, ticket_hash)
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

local function consume_cluster(conf, ticket_hash)
  local red, err = new_cluster_client(conf)
  if not red then
    return nil, err
  end

  local result, get_err = red:getdel(key(conf, ticket_hash))
  if get_err then
    return nil, "cluster GETDEL failed: " .. describe_error(get_err)
  end
  if result == nil or result == ngx.null then
    return nil, "not found"
  end
  return result
end

function _M.put(conf, ticket_hash, value)
  log_ticket_event(conf, "redis write started")
  local ok, err
  if conf.redis_cluster_enabled then
    ok, err = put_cluster(conf, ticket_hash, value)
  else
    ok, err = put_single(conf, ticket_hash, value)
  end
  if ok then
    log_ticket_event(conf, "redis write completed")
  end
  return ok, err
end

function _M.consume(conf, ticket_hash)
  log_ticket_event(conf, "redis consume started")
  local result, err
  if conf.redis_cluster_enabled then
    result, err = consume_cluster(conf, ticket_hash)
  else
    result, err = consume_single(conf, ticket_hash)
  end
  if result then
    log_ticket_event(conf, "redis consume completed")
  end
  return result, err
end

_M._build_cluster_config = build_cluster_config

return _M
