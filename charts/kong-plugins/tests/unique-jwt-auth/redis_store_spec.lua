local runner = require "runner"

_G.kong = {
  log = {
    warn = function()
    end,
  },
}

local redis = require "resty.redis"
local redis_store = require "kong.plugins.unique-jwt-auth.redis_store"
local xmodem = require "kong.plugins.unique-jwt-auth.xmodem"

local describe = runner.describe
local it = runner.it
local assert_equal = runner.assert_equal
local assert_truthy = runner.assert_truthy
local assert_falsy = runner.assert_falsy
local assert_contains = runner.assert_contains

local REDIS_HOST = assert(os.getenv("REDIS_HOST"))
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT") or "6379")
local CLUSTER_USER = assert(os.getenv("REDIS_CLUSTER_USER"))
local CLUSTER_PASSWORD = assert(os.getenv("REDIS_CLUSTER_PASSWORD"))
local MINIMAL_USER = assert(os.getenv("REDIS_CLUSTER_MINIMAL_USER"))
local MINIMAL_PASSWORD = assert(os.getenv("REDIS_CLUSTER_MINIMAL_PASSWORD"))
local SINGLE_DATABASE = 15
local KEY_PREFIX = "ws_ticket_test:"

local CLUSTER_NODES = {}
for host in assert(os.getenv("REDIS_CLUSTER_NODES")):gmatch("[^,]+") do
  CLUSTER_NODES[#CLUSTER_NODES + 1] = {
    host = host,
    port = 6379,
  }
end

local function connect(host, port)
  local red = redis:new()
  red:set_timeout(2000)
  local ok, err = red:connect(host, port or 6379)
  if not ok then
    error("Redis connect failed: " .. tostring(err))
  end
  return red
end

local function single_conf(overrides)
  local conf = {
    redis_cluster_enabled = false,
    redis_host = REDIS_HOST,
    redis_port = REDIS_PORT,
    redis_timeout = 2000,
    redis_database = SINGLE_DATABASE,
    redis_key_prefix = KEY_PREFIX,
    redis_ssl = false,
    redis_ssl_verify = true,
    ticket_ttl = 20,
  }
  for name, value in pairs(overrides or {}) do
    conf[name] = value
  end
  return conf
end

local function cluster_conf(overrides)
  local conf = {
    redis_cluster_enabled = true,
    redis_cluster_name = "ws-ticket-integration",
    redis_cluster_nodes = CLUSTER_NODES,
    redis_username = CLUSTER_USER,
    redis_password = CLUSTER_PASSWORD,
    redis_timeout = 2000,
    redis_database = 0,
    redis_key_prefix = KEY_PREFIX,
    redis_ssl = false,
    redis_ssl_verify = true,
    ticket_ttl = 20,
  }
  for name, value in pairs(overrides or {}) do
    conf[name] = value
  end
  return conf
end

local function reset_single()
  local red = connect(REDIS_HOST, REDIS_PORT)
  assert(red:select(SINGLE_DATABASE))
  assert(red:flushdb())
  red:set_keepalive(10000, 10)
end

local function ticket_hash_for_range(start_slot, end_slot)
  for number = 1, 100000 do
    local ticket_hash = "slot-" .. number
    local slot = xmodem.redis_crc(KEY_PREFIX .. ticket_hash)
    if slot >= start_slot and slot <= end_slot then
      return ticket_hash, slot
    end
  end
  error("Could not find a key in requested slot range")
end

local function cluster_slots()
  local red = connect(CLUSTER_NODES[1].host)
  local slots, err = red:cluster("slots")
  red:close()
  if not slots then
    error("CLUSTER SLOTS failed: " .. tostring(err))
  end
  return slots
end

local function move_empty_slot(slot, source_ip, target_id)
  local source
  for _, node in ipairs(CLUSTER_NODES) do
    if node.host ~= source_ip then
      local red = connect(node.host, node.port)
      local ok, err = red:cluster("setslot", slot, "node", target_id)
      red:close()
      if not ok then
        error("CLUSTER SETSLOT failed on " .. node.host .. ": " ..
          tostring(err))
      end
    else
      source = node
    end
  end

  assert_truthy(source, "source node missing from seed list")
  local red = connect(source.host, source.port)
  local ok, err = red:cluster("setslot", slot, "node", target_id)
  red:close()
  if not ok then
    error("CLUSTER SETSLOT failed on source: " .. tostring(err))
  end
end

-- source_node/target_node are CLUSTER SLOTS master tuples: {ip, port, id}.
-- Marking the target IMPORTING and the source MIGRATING makes the source
-- answer with ASK for keys that do not yet exist in the slot.
local function start_slot_migration(slot, source_node, target_node)
  local red_target = connect(target_node[1], target_node[2])
  local ok, err = red_target:cluster("setslot", slot, "importing", source_node[3])
  red_target:close()
  if not ok then
    error("CLUSTER SETSLOT IMPORTING failed: " .. tostring(err))
  end

  local red_source = connect(source_node[1], source_node[2])
  ok, err = red_source:cluster("setslot", slot, "migrating", target_node[3])
  red_source:close()
  if not ok then
    error("CLUSTER SETSLOT MIGRATING failed: " .. tostring(err))
  end
end

local function schema()
  local Schema = require "kong.db.schema"
  local consumers = Schema.new({
    name = "consumers",
    primary_key = {"id"},
    fields = {{
      id = {
        type = "string",
        required = true,
      },
    }},
  })
  if not consumers then
    error("Could not register the consumer schema dependency")
  end

  local definition = require "kong.plugins.unique-jwt-auth.schema"
  local result, err = Schema.new(definition)
  if not result then
    error("Could not load plugin schema: " .. tostring(err))
  end
  return result
end

local function schema_entity(config)
  config.allowed_iss = {"https://id.example.com"}
  config.ws_ticket_enabled = true
  config.ticket_mint_paths = {"/auth/ticket"}
  config.ticket_upgrade_paths = {"/graphql"}
  config.ticket_record_secret = config.ticket_record_secret or "secret"
  return {
    config = config,
  }
end

local function validate_schema(plugin_schema, config)
  local entity = schema_entity(config)
  entity = plugin_schema:process_auto_fields(entity, "insert")
  return plugin_schema:validate_insert(entity)
end

local function run()
  describe("single-node Redis store", function()
    it("puts and consumes a ticket once", function()
      reset_single()
      local conf = single_conf()

      local ok, put_err = redis_store.put(conf, "single", "record")
      assert_truthy(ok, put_err)

      local value, consume_err = redis_store.consume(conf, "single")
      assert_equal("record", value, consume_err)

      local replay, replay_err = redis_store.consume(conf, "single")
      assert_falsy(replay)
      assert_equal("not found", replay_err)
    end)

    it("returns connection failures", function()
      local ok, err = redis_store.put(single_conf({
        redis_host = "127.0.0.1",
        redis_port = 1,
        redis_timeout = 50,
      }), "unreachable", "record")

      assert_falsy(ok)
      assert_contains("connect failed", err)
    end)
  end)

  describe("Redis Cluster store", function()
    it("maps timeout, TLS, keepalive, and ACL options", function()
      local mapped = redis_store._build_cluster_config(cluster_conf({
        redis_ssl = true,
        redis_ssl_verify = false,
        redis_server_name = "redis.example.internal",
      }))

      assert_equal(2000, mapped.connect_timeout)
      assert_equal(2000, mapped.read_timeout)
      assert_equal(2000, mapped.send_timeout)
      assert_equal(10000, mapped.keepalive_timeout)
      assert_equal(100, mapped.keepalive_cons)
      assert_equal("redis_cluster_slot_locks", mapped.dict_name)
      assert_equal(2, mapped.lock_timeout)
      assert_equal(true, mapped.connect_opts.ssl)
      assert_equal(false, mapped.connect_opts.ssl_verify)
      assert_equal("redis.example.internal", mapped.connect_opts.server_name)
      assert_equal(CLUSTER_USER, mapped.username)
      assert_equal(CLUSTER_PASSWORD, mapped.password)
      assert_falsy(mapped.connect_opts.pool)
    end)

    it("routes tickets in ranges owned by different masters", function()
      local conf = cluster_conf()
      local slots = cluster_slots()
      assert_truthy(#slots >= 3, "expected at least three slot ranges")

      for index = 1, 3 do
        local ticket_hash = ticket_hash_for_range(
          slots[index][1],
          slots[index][2]
        )
        local value = "record-" .. index
        local ok, put_err = redis_store.put(conf, ticket_hash, value)
        assert_truthy(ok, put_err)

        local consumed, consume_err = redis_store.consume(conf, ticket_hash)
        assert_equal(value, consumed, consume_err)
      end
    end)

    it("authenticates with a named Redis ACL user", function()
      local conf = cluster_conf({
        redis_cluster_name = "ws-ticket-acl",
      })
      local ok, err = redis_store.put(conf, "acl", "record")
      assert_truthy(ok, err)
      assert_equal("record", redis_store.consume(conf, "acl"))
    end)

    it("initializes with a least-privilege ACL user lacking INFO", function()
      local conf = cluster_conf({
        redis_cluster_name = "ws-ticket-minimal",
        redis_username = MINIMAL_USER,
        redis_password = MINIMAL_PASSWORD,
      })

      local ok, put_err = redis_store.put(conf, "minimal", "record")
      assert_truthy(ok, put_err)
      assert_equal("record", redis_store.consume(conf, "minimal"))
    end)

    it("refreshes a stale slot cache after MOVED", function()
      local conf = cluster_conf()
      local slots = cluster_slots()
      local source = slots[1][3]
      local target = slots[2][3]
      local ticket_hash, slot = ticket_hash_for_range(slots[1][1], slots[1][2])

      local missing, missing_err = redis_store.consume(conf, ticket_hash)
      assert_falsy(missing)
      assert_equal("not found", missing_err)

      move_empty_slot(slot, source[1], target[3])

      local ok, put_err = redis_store.put(conf, ticket_hash, "after-move")
      assert_truthy(ok, put_err)
      assert_equal("after-move", redis_store.consume(conf, ticket_hash))
    end)

    it("follows an ASK redirect to a migrating slot", function()
      local conf = cluster_conf()
      local slots = cluster_slots()
      assert_truthy(#slots >= 2, "expected at least two slot ranges")
      local source = slots[1][3]
      local target = slots[2][3]
      local ticket_hash, slot = ticket_hash_for_range(slots[1][1], slots[1][2])

      -- prime the slot cache while the source still owns the slot
      local primed, primed_err = redis_store.consume(conf, ticket_hash)
      assert_falsy(primed)
      assert_equal("not found", primed_err)

      start_slot_migration(slot, source, target)

      -- the key is missing on the source, so SET is answered with ASK and must
      -- authenticate, send ASKING, and execute on the importing target
      local ok, put_err = redis_store.put(conf, ticket_hash, "asked")
      assert_truthy(ok, put_err)

      -- GETDEL also resolves through ASK and consumes the ticket exactly once
      assert_equal("asked", redis_store.consume(conf, ticket_hash))

      local replay, replay_err = redis_store.consume(conf, ticket_hash)
      assert_falsy(replay)
      assert_equal("not found", replay_err)

      -- finalize the now-empty slot on the target for later tests
      move_empty_slot(slot, source[1], target[3])
    end)

    it("returns discovery failures", function()
      local ok, err = redis_store.put(cluster_conf({
        redis_cluster_name = "ws-ticket-unreachable",
        redis_cluster_nodes = {{
          host = "127.0.0.1",
          port = 1,
        }},
        redis_timeout = 50,
      }), "unreachable", "record")

      assert_falsy(ok)
      assert_contains("cluster client initialization failed", err)
    end)
  end)

  describe("plugin schema Redis modes", function()
    local plugin_schema = schema()

    it("requires redis_host in single-node mode", function()
      local ok = validate_schema(plugin_schema, {
        redis_cluster_enabled = false,
      })
      assert_falsy(ok)
    end)

    it("accepts cluster mode without redis_host", function()
      local ok, err = validate_schema(plugin_schema, {
        redis_cluster_enabled = true,
        redis_cluster_name = "schema-cluster",
        redis_cluster_nodes = {{
          host = "redis-0.example.internal",
          port = 6379,
        }},
        redis_database = 0,
      })
      assert_truthy(ok, require("cjson.safe").encode(err))
    end)

    it("rejects missing cluster identity and nodes", function()
      local ok = validate_schema(plugin_schema, {
        redis_cluster_enabled = true,
        redis_database = 0,
      })
      assert_falsy(ok)
    end)

    it("rejects a non-zero database in cluster mode", function()
      local ok = validate_schema(plugin_schema, {
        redis_cluster_enabled = true,
        redis_cluster_name = "schema-cluster",
        redis_cluster_nodes = {{
          host = "redis-0.example.internal",
          port = 6379,
        }},
        redis_database = 7,
      })
      assert_falsy(ok)
    end)
  end)
end

return run
