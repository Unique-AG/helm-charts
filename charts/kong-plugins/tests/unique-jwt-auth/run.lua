-- Entry point for the unique-jwt-auth specs. See run.sh.
--
-- The resty CLI wraps the main chunk in xpcall (init_worker), which forbids
-- cosocket yields. Schedule the suite on a timer + light thread so Redis can
-- yield. Specs are required first (definition only) and run() afterward —
-- cosockets cannot run while still inside require().
package.path = "/spec/?.lua;" .. package.path

local finished = false
local exit_code = 1

io.stdout:setvbuf("no")
io.stderr:setvbuf("no")

local ok, err = ngx.timer.at(0, function(premature)
    if premature then
        finished = true
        return
    end

    local thread, spawn_err = ngx.thread.spawn(function()
        local runner = require "runner"
        local run_specs = require "handler_spec"
        run_specs()
        return runner.report()
    end)

    if not thread then
        io.stderr:write("failed to spawn test thread: " .. tostring(spawn_err) .. "\n")
        exit_code = 1
        finished = true
        return
    end

    local waited, result = ngx.thread.wait(thread)
    if waited then
        exit_code = result
    else
        if type(result) == "table" then
            local cjson = require "cjson.safe"
            io.stderr:write("FATAL: " .. (cjson.encode(result) or tostring(result)) .. "\n")
        else
            io.stderr:write("FATAL: " .. tostring(result) .. "\n")
        end
        exit_code = 1
    end
    finished = true
end)

if not ok then
    io.stderr:write("failed to schedule test timer: " .. tostring(err) .. "\n")
    os.exit(1)
end

local deadline = ngx.now() + 90
while not finished and ngx.now() < deadline do
    ngx.sleep(0.05)
end

if not finished then
    io.stderr:write("test suite timed out\n")
    os.exit(1)
end

os.exit(exit_code)
