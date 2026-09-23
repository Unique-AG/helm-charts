local cjson = require "cjson.safe"
local redis = require "resty.redis"
local resty_sha256 = require "resty.sha256"
local to_hex = require "resty.string".to_hex
local openssl_hmac = require "resty.openssl.hmac"

local runner = require "runner"
local redis_store = require "kong.plugins.unique-jwt-auth.redis_store"
local ws_ticket = require "kong.plugins.unique-jwt-auth.ws_ticket"

local describe = runner.describe
local it = runner.it
local assert_equal = runner.assert_equal
local assert_truthy = runner.assert_truthy
local assert_falsy = runner.assert_falsy

local REDIS_HOST = assert(os.getenv("REDIS_HOST"))
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT") or "6379")
local SINGLE_DATABASE = 14
local KEY_PREFIX = "ws_ticket_spec:"
local SECRET = "ticket-record-secret"

local function sha256_hex(value)
  local sha = resty_sha256:new()
  sha:update(value)
  return to_hex(sha:final())
end

local function hmac_sha256_hex(secret, value)
  local hmac = assert(openssl_hmac.new(secret, "sha256"))
  return to_hex(assert(hmac:final(value)))
end

local function connect()
  local red = redis:new()
  red:set_timeout(2000)
  local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
  if not ok then
    error("Redis connect failed: " .. tostring(err))
  end
  return red
end

local function reset_single()
  local red = connect()
  assert(red:select(SINGLE_DATABASE))
  assert(red:flushdb())
  red:set_keepalive(10000, 10)
end

local function conf(overrides)
  local result = {
    consumer_match = false,
    redis_cluster_enabled = false,
    redis_host = REDIS_HOST,
    redis_port = REDIS_PORT,
    redis_timeout = 2000,
    redis_database = SINGLE_DATABASE,
    redis_key_prefix = KEY_PREFIX,
    redis_ssl = false,
    redis_ssl_verify = true,
    ticket_ttl = 20,
    ticket_param_name = "ticket",
    ticket_mint_paths = {"/auth/ticket"},
    ticket_mint_path_suffixes = {},
    ticket_upgrade_paths = {"/graphql"},
    ticket_upgrade_path_suffixes = {},
    ticket_allowed_origins = {},
    ticket_record_secret = SECRET,
  }
  for name, value in pairs(overrides or {}) do
    result[name] = value
  end
  return result
end

local function reset_kong(shared, consumers)
  local state = {
    authenticated_consumer = nil,
    authenticated_credential = nil,
    cleared_headers = {},
    consumers = consumers or {},
    headers = {
      connection = "Upgrade",
      upgrade = "websocket",
      ["x-user-roles"] = "spoofed-role",
      ["x-company-name"] = "spoofed-company",
      ["x-consumer-id"] = "spoofed-consumer",
    },
    query = {},
    query_set = nil,
    set_headers = {},
  }

  _G.kong = {
    cache = {
      get = function(_, _, _, _, consumer_id)
        return state.consumers[consumer_id]
      end,
    },
    client = {
      authenticate = function(consumer, credential)
        state.authenticated_consumer = consumer
        state.authenticated_credential = credential
      end,
      load_consumer = function()
        error("cache mock must resolve consumers directly")
      end,
    },
    ctx = {
      shared = shared or {
        user_id = "user-1",
        company_id = "company-1",
      },
    },
    db = {
      consumers = {
        cache_key = function(_, consumer_id)
          return "consumer:" .. consumer_id
        end,
      },
    },
    log = {
      debug = function() end,
      err = function() end,
      warn = function() end,
    },
    request = {
      get_method = function()
        return "POST"
      end,
      get_path = function()
        return "/auth/ticket"
      end,
      get_query = function()
        return state.query
      end,
      get_header = function(name)
        return state.headers[name:lower()]
      end,
    },
    service = {
      request = {
        clear_header = function(name)
          state.cleared_headers[name:lower()] = true
          state.set_headers[name:lower()] = nil
        end,
        set_header = function(name, value)
          state.set_headers[name:lower()] = value
        end,
        set_query = function(query)
          state.query_set = query
        end,
      },
    },
  }

  return state
end

local function valid_envelope(ticket_hash, record)
  local record_json = assert(cjson.encode(record))
  return assert(cjson.encode({
    r = record_json,
    m = hmac_sha256_hex(SECRET, ticket_hash .. "." .. record_json),
  }))
end

local function put_record(cfg, ticket, record)
  local ticket_hash = sha256_hex(ticket)
  record.exp = record.exp or (ngx.time() + cfg.ticket_ttl)
  return redis_store.put(
    cfg,
    ticket_hash,
    valid_envelope(ticket_hash, record)
  )
end

local function consume(cfg, state, ticket)
  state.query = {
    ticket = ticket,
    other = "kept",
  }
  return ws_ticket.do_authentication(cfg, ticket)
end

local function run()
  describe("WebSocket ticket authentication context", function()
    it("restores identity, roles, and matched consumer context", function()
      reset_single()
      local consumer = {
        id = "consumer-1",
        custom_id = "consumer-custom",
        username = "consumer-name",
      }
      local state = reset_kong({
        user_id = "user-1",
        company_id = "company-1",
        company_name = "Example Company",
        company_domain = "example.com",
        user_roles = {"CHAT_CHAT_BASIC", "CHAT_CHAT_UNLIMITED"},
        consumer_id = consumer.id,
      }, {
        [consumer.id] = consumer,
      })
      local cfg = conf({
        consumer_match = true,
      })

      local created, create_err = ws_ticket.create_ticket(cfg)
      assert_truthy(created, cjson.encode(create_err))

      local ok, auth_err = consume(cfg, state, created.ticket)
      assert_truthy(ok, cjson.encode(auth_err))
      assert_equal("user-1", state.set_headers["x-user-id"])
      assert_equal("company-1", state.set_headers["x-company-id"])
      assert_equal("Example Company", state.set_headers["x-company-name"])
      assert_equal("example.com", state.set_headers["x-company-domain"])
      assert_equal(
        "CHAT_CHAT_BASIC,CHAT_CHAT_UNLIMITED",
        state.set_headers["x-user-roles"]
      )
      assert_equal("consumer-1", state.set_headers["x-consumer-id"])
      assert_equal(
        "consumer-custom",
        state.set_headers["x-consumer-custom-id"]
      )
      assert_equal("consumer-name", state.set_headers["x-consumer-username"])
      assert_equal(true, state.set_headers["x-anonymous-consumer"])
      assert_truthy(state.cleared_headers["x-credential-identifier"])
      assert_equal(consumer, state.authenticated_consumer)
      assert_equal(nil, state.authenticated_credential)
      assert_equal(nil, state.query_set.ticket)
      assert_equal("kept", state.query_set.other)

      local replay, replay_err = ws_ticket.do_authentication(
        cfg,
        created.ticket
      )
      assert_falsy(replay)
      assert_equal("ws_ticket_unknown", replay_err.warning_reason)
    end)

    it("accepts minimal signed records and clears unsupported headers", function()
      reset_single()
      local state = reset_kong()
      local cfg = conf()
      local ticket = "legacy-ticket"

      assert_truthy(put_record(cfg, ticket, {
        user_id = "legacy-user",
        company_id = "legacy-company",
      }))

      local ok, auth_err = consume(cfg, state, ticket)
      assert_truthy(ok, cjson.encode(auth_err))
      assert_equal("legacy-user", state.set_headers["x-user-id"])
      assert_equal("legacy-company", state.set_headers["x-company-id"])
      assert_equal(nil, state.set_headers["x-user-roles"])
      assert_equal(nil, state.set_headers["x-company-name"])
      assert_equal(nil, state.set_headers["x-company-domain"])
      assert_truthy(state.cleared_headers["x-user-roles"])
      assert_truthy(state.cleared_headers["x-company-name"])
      assert_truthy(state.cleared_headers["x-company-domain"])
      assert_truthy(state.cleared_headers["x-consumer-id"])
      assert_equal(nil, state.authenticated_consumer)
    end)

    it("omits an empty role list from minted tickets", function()
      reset_single()
      local state = reset_kong({
        user_id = "user-1",
        company_id = "company-1",
        company_name = "Example Company",
        company_domain = "example.com",
        user_roles = {},
      })
      local cfg = conf()

      local created, create_err = ws_ticket.create_ticket(cfg)
      assert_truthy(created, cjson.encode(create_err))

      local ok, auth_err = consume(cfg, state, created.ticket)
      assert_truthy(ok, cjson.encode(auth_err))
      assert_equal(nil, state.set_headers["x-user-roles"])
      assert_truthy(state.cleared_headers["x-user-roles"])
    end)

    it("rejects malformed optional identity fields", function()
      reset_single()
      local state = reset_kong()
      local cfg = conf()
      local ticket = "malformed-ticket"

      assert_truthy(put_record(cfg, ticket, {
        user_id = "user-1",
        company_id = "company-1",
        user_roles = "CHAT_CHAT_BASIC",
      }))

      local ok, auth_err = consume(cfg, state, ticket)
      assert_falsy(ok)
      assert_equal("ws_ticket_unknown", auth_err.warning_reason)
      assert_equal(nil, state.set_headers["x-user-id"])
    end)

    it("rejects a matched consumer that no longer exists", function()
      reset_single()
      local state = reset_kong({
        user_id = "user-1",
        company_id = "company-1",
        consumer_id = "deleted-consumer",
      })
      local cfg = conf({
        consumer_match = true,
      })

      local created, create_err = ws_ticket.create_ticket(cfg)
      assert_truthy(created, cjson.encode(create_err))

      local ok, auth_err = consume(cfg, state, created.ticket)
      assert_falsy(ok)
      assert_equal("ws_ticket_unknown", auth_err.warning_reason)
      assert_equal(nil, state.set_headers["x-user-id"])
    end)

    it("rejects consumer identity when matching is disabled", function()
      reset_single()
      local state = reset_kong()
      local cfg = conf()
      local ticket = "unexpected-consumer"

      assert_truthy(put_record(cfg, ticket, {
        user_id = "user-1",
        company_id = "company-1",
        consumer_id = "consumer-1",
      }))

      local ok, auth_err = consume(cfg, state, ticket)
      assert_falsy(ok)
      assert_equal("ws_ticket_unknown", auth_err.warning_reason)
      assert_equal(nil, state.set_headers["x-consumer-id"])
    end)
  end)
end

return run
