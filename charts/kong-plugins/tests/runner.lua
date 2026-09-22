-------------------------------------------------------------------------------
-- Minimal spec runner for the official Kong image.
--
-- Specs run under `resty` so they get a real ngx API. The Kong image has no C
-- toolchain, so busted cannot be installed there; this provides the small
-- describe/it/assert subset the plugin specs use.
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
    -- Specs run inside an ngx.timer + light thread (see run.lua), which
    -- allows cosocket yields. Do not wrap in pcall/xpcall — those cross a
    -- C-call boundary and reject yields. A failing assertion aborts the
    -- suite; that is acceptable for this harness.
    fn()
    passed = passed + 1
    io.write(".")
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

function M.assert_contains(needle, haystack, context)
    if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
        error(string.format("%sexpected %s to contain %s", context and (context .. ": ") or "",
            describe_value(haystack), describe_value(needle)), 2)
    end
end

function M.assert_none_contains(needle, list, context)
    for _, entry in ipairs(list) do
        if type(entry) == "string" and entry:find(needle, 1, true) then
            error(string.format("%sexpected nothing to contain %s, but found %s",
                context and (context .. ": ") or "", describe_value(needle), describe_value(entry)), 2)
        end
    end
end

function M.assert_any_contains(needle, list, context)
    for _, entry in ipairs(list) do
        if type(entry) == "string" and entry:find(needle, 1, true) then
            return
        end
    end
    error(string.format("%sexpected one of %d entries to contain %s", context and (context .. ": ") or "", #list,
        describe_value(needle)), 2)
end

function M.report()
    io.write("\n\n")
    for _, failure in ipairs(failures) do
        io.write(string.format("FAILED: %s\n  %s\n    %s\n\n", failure.group, failure.name, failure.err))
    end
    io.write(string.format("%d passed, %d failed\n", passed, #failures))
    return #failures == 0 and 0 or 1
end

return M
