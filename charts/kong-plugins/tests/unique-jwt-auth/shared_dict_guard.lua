_G.kong = {
  log = {
    warn = function()
    end,
  },
}

local redis_store = require "kong.plugins.unique-jwt-auth.redis_store"

local ok, err = redis_store.put({
  redis_cluster_enabled = true,
  redis_cluster_name = "missing-shdict",
  redis_cluster_nodes = {{
    host = "127.0.0.1",
    port = 6379,
  }},
  redis_timeout = 50,
  redis_database = 0,
  redis_key_prefix = "ws_ticket_test:",
  redis_ssl = false,
  redis_ssl_verify = true,
  ticket_ttl = 20,
}, "guard", "record")

if ok or type(err) ~= "string"
  or not err:find("is not configured", 1, true)
then
  io.stderr:write("unexpected shared dictionary guard result: " ..
    tostring(ok) .. ", " .. tostring(err) .. "\n")
  os.exit(1)
end

io.write("shared dictionary guard passed\n")
