-------------------------------------------------------------------------------
-- Minimal spec runner.
--
-- The specs run inside the official Kong image so that they exercise the same
-- OpenResty, cjson and resty.openssl the plugin will actually run against.
-- That image ships luarocks but no C toolchain, and busted's dependency chain
-- needs one, so busted cannot be installed there. Rather than maintain a
-- separate build image purely to get describe/it, this provides the small
-- subset of that API the plugin specs use.
--
-- Everything runs under the `resty` CLI, which is what gives the specs a real
-- ngx API (ngx.time, ngx.encode_base64, ngx.re) to test against.
-------------------------------------------------------------------------------

local M = {}

local passed = 0
local failures = {}
local group = "(root)"

function M.describe(name, fn)
    local previous = group
    group = previous == "(root)" and name or (previous .. " " .. name)
    fn()
    group = previous
end

function M.it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        io.write(".")
    else
        failures[#failures + 1] = {
            group = group,
            name = name,
            err = tostring(err)
        }
        io.write("F")
    end
    io.flush()
end

local function describe_value(value)
    if type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

function M.assert_equal(expected, actual, context)
    if expected ~= actual then
        error(string.format("%sexpected %s but got %s", context and (context .. ": ") or "", describe_value(expected),
            describe_value(actual)), 2)
    end
end

function M.assert_truthy(value, context)
    if not value then
        error(string.format("%sexpected a truthy value but got %s", context and (context .. ": ") or "",
            describe_value(value)), 2)
    end
end

function M.assert_falsy(value, context)
    if value then
        error(string.format("%sexpected a falsy value but got %s", context and (context .. ": ") or "",
            describe_value(value)), 2)
    end
end

--- Assert that `haystack` contains `needle` as a plain substring.
function M.assert_contains(needle, haystack, context)
    if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
        error(string.format("%sexpected %s to contain %s", context and (context .. ": ") or "",
            describe_value(haystack), describe_value(needle)), 2)
    end
end

--- Assert that no entry of `list` contains `needle`.
function M.assert_none_contains(needle, list, context)
    for _, entry in ipairs(list) do
        if type(entry) == "string" and entry:find(needle, 1, true) then
            error(string.format("%sexpected nothing to contain %s, but found %s",
                context and (context .. ": ") or "", describe_value(needle), describe_value(entry)), 2)
        end
    end
end

--- Assert that at least one entry of `list` contains `needle`.
function M.assert_any_contains(needle, list, context)
    for _, entry in ipairs(list) do
        if type(entry) == "string" and entry:find(needle, 1, true) then
            return
        end
    end
    error(string.format("%sexpected one of %d entries to contain %s", context and (context .. ": ") or "", #list,
        describe_value(needle)), 2)
end

--- Print the summary and return the process exit code.
function M.report()
    io.write("\n\n")
    for _, failure in ipairs(failures) do
        io.write(string.format("FAILED: %s\n  %s\n    %s\n\n", failure.group, failure.name, failure.err))
    end
    io.write(string.format("%d passed, %d failed\n", passed, #failures))
    return #failures == 0 and 0 or 1
end

return M
