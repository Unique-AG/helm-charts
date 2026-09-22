local runner = require "runner"
local cjson = require "cjson.safe"

local user_roles = require "kong.plugins.unique-app-repo-auth.user_roles"

local describe = runner.describe
local it = runner.it
local assert_equal = runner.assert_equal
local assert_contains = runner.assert_contains

return function()
    describe("user_roles.format", function()
        it("passes a comma-separated string through unchanged", function()
            local roles = user_roles.format("chat.chat.basic,chat.debug.read")
            -- The bug this plugin shipped: cjson.encode() added wrapping quotes
            -- here, so a downstream split(",") corrupted the first and last role.
            assert_equal("chat.chat.basic,chat.debug.read", roles)
        end)

        it("passes a single role through unchanged", function()
            assert_equal("chat.debug.read", user_roles.format("chat.debug.read"))
        end)

        it("joins a string array with commas", function()
            assert_equal("chat.chat.basic,chat.debug.read",
                user_roles.format({ "chat.chat.basic", "chat.debug.read" }))
        end)

        it("reports nil as missing", function()
            local roles, reason = user_roles.format(nil)
            assert_equal(nil, roles)
            assert_equal(user_roles.MISSING, reason)
        end)

        it("reports decoded JSON null as missing", function()
            local body = cjson.decode('{"roles":null}')
            local roles, reason = user_roles.format(body.roles)
            -- cjson decodes null to a lightuserdata sentinel, which is truthy.
            assert_equal(nil, roles)
            assert_equal(user_roles.MISSING, reason)
        end)

        it("reports an empty string as empty", function()
            local roles, reason = user_roles.format("")
            assert_equal(nil, roles)
            assert_equal(user_roles.EMPTY, reason)
        end)

        it("reports an empty array as empty", function()
            local roles, reason = user_roles.format({})
            assert_equal(nil, roles)
            assert_equal(user_roles.EMPTY, reason)
        end)

        it("rejects a JSON object instead of dropping its keys", function()
            local body = cjson.decode('{"roles":{"chat.debug.read":true}}')
            local roles, reason, detail = user_roles.format(body.roles)
            assert_equal(nil, roles)
            assert_equal(user_roles.UNEXPECTED, reason)
            assert_contains("object", detail)
        end)

        it("rejects an array holding a non-string", function()
            local roles, reason, detail = user_roles.format({ "chat.debug.read", true })
            assert_equal(nil, roles)
            assert_equal(user_roles.UNEXPECTED, reason)
            assert_contains("roles[2]", detail)
        end)

        it("rejects an array holding a nested table", function()
            local roles, reason = user_roles.format({ { "chat.debug.read" } })
            assert_equal(nil, roles)
            assert_equal(user_roles.UNEXPECTED, reason)
        end)

        it("rejects an array holding JSON null", function()
            local body = cjson.decode('{"roles":["chat.debug.read",null]}')
            local roles, reason = user_roles.format(body.roles)
            assert_equal(nil, roles)
            assert_equal(user_roles.UNEXPECTED, reason)
        end)

        it("rejects an array holding an empty string", function()
            local roles, reason = user_roles.format({ "chat.debug.read", "" })
            assert_equal(nil, roles)
            assert_equal(user_roles.UNEXPECTED, reason)
        end)

        it("rejects an array entry that already contains a comma", function()
            local roles, reason = user_roles.format({ "chat.chat.basic,chat.debug.read" })
            assert_equal(nil, roles)
            assert_equal(user_roles.UNEXPECTED, reason)
        end)

        it("rejects a boolean", function()
            local roles, reason, detail = user_roles.format(true)
            assert_equal(nil, roles)
            assert_equal(user_roles.UNEXPECTED, reason)
            assert_contains("boolean", detail)
        end)

        it("rejects a number", function()
            local roles, reason = user_roles.format(42)
            assert_equal(nil, roles)
            assert_equal(user_roles.UNEXPECTED, reason)
        end)

        it("never leaks role values into the logged detail", function()
            local _, _, detail = user_roles.format({ "chat.debug.read", 42 })
            if detail:find("chat.debug.read", 1, true) then
                error("detail leaked a role value: " .. detail)
            end
        end)
    end)
end
