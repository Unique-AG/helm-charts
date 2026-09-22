-- Entry point for the unique-app-repo-auth specs. See run.sh.
--
-- Unlike the unique-jwt-auth suite these specs touch no cosockets, so they run
-- directly in the main chunk without a timer + light thread.
package.path = "/spec/?.lua;/shared/?.lua;" .. package.path

io.stdout:setvbuf("no")
io.stderr:setvbuf("no")

local runner = require "runner"
require "user_roles_spec"()

os.exit(runner.report())
