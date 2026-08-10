-- Entry point for the unique-jwt-auth specs. See run.sh.
package.path = "/spec/?.lua;" .. package.path

local runner = require "runner"

require "ws_ticket_spec"
require "handler_spec"

os.exit(runner.report())
