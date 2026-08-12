local typedefs = require "kong.db.schema.typedefs"

local PLUGIN_NAME = "unique-jwt-auth"

local schema = {
    name = PLUGIN_NAME,
    fields = {{
        -- this plugin will only be applied to Services or Routes
        consumer = typedefs.no_consumer
    }, {
        -- this plugin will only run within Nginx HTTP module
        protocols = typedefs.protocols_http
    }, {
        config = {
            type = "record",
            fields = {{
                uri_param_names = {
                    -- description = "A list of querystring parameters that Kong will inspect to retrieve JWTs.",
                    type = "set",
                    elements = {
                        type = "string"
                    },
                    default = {"jwt"}
                }
            }, {
                cookie_names = {
                    -- description = "A list of cookie names that Kong will inspect to retrieve JWTs.",
                    type = "set",
                    elements = {
                        type = "string"
                    },
                    default = {}
                }
            }, {
                header_names = {
                    -- description = "A list of HTTP header names that Kong will inspect to retrieve JWTs.",
                    type = "set",
                    elements = {
                        type = "string"
                    },
                    default = {"authorization"}
                }
            }, {
                claims_to_verify = {
                    -- description = "A list of registered claims (according to RFC 7519) that Kong can verify as well. Accepted values: one of exp or nbf.",
                    type = "set",
                    elements = {
                        type = "string",
                        one_of = {"exp", "nbf"}
                    },
                    default = {"exp", "nbf"}
                }
            }, {
                maximum_expiration = {
                    -- description = "A value between 0 and 31536000 (365 days) limiting the lifetime of the JWT to maximum_expiration seconds in the future.",
                    type = "number",
                    default = 0,
                    between = {0, 31536000}
                }
            }, {
                anonymous = {
                    -- description = "An optional string (consumer UUID or username) value to use as an anonymous consumer if authentication fails.",
                    type = "string"
                }
            }, {
                run_on_preflight = {
                    -- description = "A boolean value that indicates whether the plugin should run (and try to authenticate) on OPTIONS preflight requests. If set to false, then OPTIONS requests will always be allowed.",
                    type = "boolean",
                    required = true,
                    default = true
                }
            }, {
                algorithm = {
                    type = "string",
                    required = true,
                    default = "RS256"
                }
            }, {
                allowed_iss = {
                    type = "set",
                    elements = {
                        type = "string"
                    },
                    required = true
                }
            }, {
                iss_key_grace_period = {
                    type = "number",
                    default = 10,
                    between = {1, 60}
                }
            }, {
                well_known_template = {
                    type = "string",
                    default = "%s/.well-known/openid-configuration"
                }
            }, {
                jwks_uri = {
                    -- description = "Directly configure the JWKS URI, bypassing the well-known endpoint discovery.",
                    type = "string"
                }
            }, {
                well_known_extra_headers = {
                    -- description = "Extra headers to send for the .well-known request.",
                    type = "map",
                    keys = { type = "string" },
                    values = { type = "string" },
                    default = {}
                }
            }, {
                jwks_extra_headers = {
                    -- description = "Extra headers to send for the jwks_uri request.",
                    type = "map",
                    keys = { type = "string" },
                    values = { type = "string" },
                    default = {}
                }
            }, {
                ssl_verify = {
                    type = "boolean",
                    default = true
                }
            }, {
                zitadel_project_id = {
                    type = "string"
                }
            }, {
                consumer_match = {
                    type = "boolean",
                    default = false
                }
            }, {
                consumer_match_claim = {
                    type = "string",
                    default = "azp"
                }
            }, {
                consumer_match_claim_custom_id = {
                    type = "boolean",
                    default = false
                }
            }, {
                consumer_match_ignore_not_found = {
                    type = "boolean",
                    default = false
                }
            }, {
                security_warning_metric_name = {
                    type = "string",
                    default = "unique_jwt_auth_security_warnings_total"
                }
            }, {
                -- Single-use opaque WebSocket tickets (Redis-backed).
                -- Default false: existing ?token= / cookie / Authorization flow unchanged.
                ws_ticket_enabled = {
                    type = "boolean",
                    default = false,
                    required = true
                }
            }, {
                ticket_param_name = {
                    type = "string",
                    default = "ticket"
                }
            }, {
                ticket_mint_path = {
                    type = "string",
                    default = "/auth/ticket"
                }
            }, {
                ticket_ttl = {
                    type = "number",
                    default = 20,
                    between = {5, 60}
                }
            }, {
                -- Route/service binding written into the ticket record and
                -- checked on consume so a chat ticket cannot open another socket.
                ticket_scope = {
                    type = "string"
                }
            }, {
                ticket_allowed_origins = {
                    type = "set",
                    elements = {
                        type = "string"
                    },
                    default = {}
                }
            }, {
                -- Max mint requests per authenticated subject per 60s window.
                -- 0 disables the limit.
                ticket_mint_rate_limit = {
                    type = "number",
                    default = 60,
                    between = {0, 10000}
                }
            }, {
                -- Max failed consumptions per client IP per 60s window.
                -- 0 disables the limit.
                ticket_fail_rate_limit = {
                    type = "number",
                    default = 30,
                    between = {0, 10000}
                }
            }, {
                redis_host = {
                    type = "string"
                }
            }, {
                redis_port = {
                    type = "number",
                    default = 6379,
                    between = {1, 65535}
                }
            }, {
                redis_ssl = {
                    type = "boolean",
                    default = false
                }
            }, {
                redis_ssl_verify = {
                    type = "boolean",
                    default = true
                }
            }, {
                redis_password = {
                    type = "string",
                    referenceable = true,
                    encrypted = true
                }
            }, {
                redis_timeout_ms = {
                    type = "number",
                    default = 2000,
                    between = {50, 60000}
                }
            }, {
                redis_database = {
                    type = "number",
                    default = 0,
                    between = {0, 15}
                }
            }, {
                redis_key_prefix = {
                    type = "string",
                    default = "ws_ticket:"
                }
            }}
        }
    }}
}

return schema
