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
local OTHER_SECRET = "wrong-ticket-record-secret"

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

local function reset_kong()
  local state = {
    query = {},
    headers = {
      connection = "Upgrade",
      upgrade = "websocket",
    },
    set_headers = {},
    cleared_headers = {},
    query_set = nil,
  }

  _G.kong = {
    ctx = {
      shared = {
        user_id = "user-1",
        company_id = "company-1",
      },
    },
    log = {
      warn = function() end,
      err = function() end,
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
        set_header = function(name, value)
          state.set_headers[name:lower()] = value
        end,
        clear_header = function(name)
          state.cleared_headers[name:lower()] = true
        end,
        set_query = function(query)
          state.query_set = query
        end,
      },
    },
  }

  return state
end

local function valid_envelope(ticket_hash, record, secret)
  local record_json = assert(cjson.encode(record))
  return assert(cjson.encode({
    r = record_json,
    m = hmac_sha256_hex(secret or SECRET, ticket_hash .. "." .. record_json),
  }))
end

local function run()
  describe("WebSocket ticket record authentication", function()
    it("mints and consumes an authenticated ticket once", function()
      reset_single()
      local state = reset_kong()
      local cfg = conf()

      local created, create_err = ws_ticket.create_ticket(cfg)
      assert_truthy(created, cjson.encode(create_err))
      assert_equal(20, created.expires_in)

      state.query = {
        ticket = created.ticket,
        other = "kept",
      }
      local ok, auth_err = ws_ticket.do_authentication(cfg, created.ticket)
      assert_truthy(ok, cjson.encode(auth_err))
      assert_equal("user-1", state.set_headers["x-user-id"])
      assert_equal("company-1", state.set_headers["x-company-id"])
      assert_truthy(state.cleared_headers["x-user-roles"])
      assert_equal(nil, state.query_set.ticket)
      assert_equal("kept", state.query_set.other)

      local replay, replay_err = ws_ticket.do_authentication(cfg, created.ticket)
      assert_falsy(replay)
      assert_equal("ws_ticket_unknown", replay_err.warning_reason)
    end)

    it("rejects a record written directly into Redis", function()
      reset_single()
      reset_kong()
      local cfg = conf()
      local ticket = "attacker-ticket"
      local ticket_hash = sha256_hex(ticket)

      local ok, put_err = redis_store.put(cfg, ticket_hash, cjson.encode({
        user_id = "victim",
        company_id = "victim-company",
      }))
      assert_truthy(ok, put_err)

      local authenticated, err = ws_ticket.do_authentication(cfg, ticket)
      assert_falsy(authenticated)
      assert_equal("ws_ticket_forged", err.warning_reason)
    end)

    it("rejects a valid record copied to another key", function()
      reset_single()
      reset_kong()
      local cfg = conf()
      local real_ticket = "real-ticket"
      local copied_ticket = "copied-ticket"
      local real_hash = sha256_hex(real_ticket)
      local copied_hash = sha256_hex(copied_ticket)
      local envelope = valid_envelope(real_hash, {
        user_id = "user-1",
        company_id = "company-1",
        exp = ngx.time() + 20,
      })

      assert_truthy(redis_store.put(cfg, copied_hash, envelope))
      local authenticated, err = ws_ticket.do_authentication(cfg, copied_ticket)
      assert_falsy(authenticated)
      assert_equal("ws_ticket_forged", err.warning_reason)
    end)

    it("rejects a record signed with the wrong secret", function()
      reset_single()
      reset_kong()
      local cfg = conf()
      local ticket = "wrong-secret-ticket"
      local ticket_hash = sha256_hex(ticket)
      local envelope = valid_envelope(ticket_hash, {
        user_id = "user-1",
        company_id = "company-1",
        exp = ngx.time() + 20,
      }, OTHER_SECRET)

      assert_truthy(redis_store.put(cfg, ticket_hash, envelope))
      local authenticated, err = ws_ticket.do_authentication(cfg, ticket)
      assert_falsy(authenticated)
      assert_equal("ws_ticket_forged", err.warning_reason)
    end)

    it("rejects an expired record even if Redis still holds the key", function()
      reset_single()
      reset_kong()
      local cfg = conf({
        ticket_ttl = 60,
      })
      local ticket = "expired-ticket"
      local ticket_hash = sha256_hex(ticket)
      local envelope = valid_envelope(ticket_hash, {
        user_id = "user-1",
        company_id = "company-1",
        exp = ngx.time() - 1,
      })

      assert_truthy(redis_store.put(cfg, ticket_hash, envelope))
      local authenticated, err = ws_ticket.do_authentication(cfg, ticket)
      assert_falsy(authenticated)
      assert_equal("ws_ticket_expired", err.warning_reason)
    end)
  end)
end

return run
