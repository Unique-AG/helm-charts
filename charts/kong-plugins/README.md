# kong-plugins

The 'kong-plugins' chart provides a streamlined solution for deploying Kong plugins via ConfigMaps to be used with the Unique Software.

Refer to each plugins readme section to learn more about them.

Please report any security concerns with the plugins via the [Security Policy](https://github.com/Unique-AG/helm-charts/tree/main?tab=security-ov-file).

![Version: 2.5.0](https://img.shields.io/badge/Version-2.5.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

## Implementation Details

### OCI Availability

New releases are published as OCI artifacts only. The Helm repository index is frozen and will not receive new versions—see the [repository README](https://github.com/Unique-AG/helm-charts/blob/main/README.md#migrating-to-oci) for migration steps.

```sh
helm install my-kong-plugins oci://ghcr.io/unique-ag/helm-charts/kong-plugins --version 2.5.0
```

<details>
<summary>Legacy Helm repository (frozen, no new versions)</summary>

```sh
helm repo add unique https://unique-ag.github.io/helm-charts/
helm install my-kong-plugins unique/kong-plugins --version 2.5.0
```

</details>

### kong-plugin-unique-jwt-auth
This plugin is a modified fork of [kong-plugin-jwt-keycloak](https://github.com/telekom-digioss/kong-plugin-jwt-keycloak) (Apache License 2.0 licensed) 🎖️

#### Cluster-Internal JWT Validation

This chart can configure Kong's JWT plugin to validate tokens using an identity provider (IdP) running within the same Kubernetes cluster, without _Hairpin Routing_. This is useful in scenarios where the IdP is not publicly accessible or when you want to ensure traffic stays within the cluster network.

To achieve this:

1.  **Specify the JWKS URI directly:** Instead of letting the plugin discover the JWKS endpoint via the IdP's well-known configuration endpoint, you can provide the internal service URL directly using the `config.jwks_uri` value. This bypasses the well-known lookup. For example, if your IdP's JWKS endpoint is available internally at `http://my-idp-service.default.svc.cluster.local/jwks`, set `config.jwks_uri` to this value.

2.  **Disable TLS verification for cluster-internal traffic:** By default, the plugin enforces TLS verification (`config.ssl_verify: true`) and requires HTTPS for all OIDC endpoints. For cluster-internal setups where the IdP communicates over plain HTTP (e.g., mTLS is handled at the mesh level rather than the application layer), set `config.ssl_verify: false`. This disables both SSL certificate validation and the HTTPS-only requirement for the JWKS and well-known endpoints.

3.  **(Optional) Add custom headers:** If your internal IdP endpoints (either the well-known endpoint or the direct JWKS endpoint) require specific headers for authentication, routing, or other purposes (e.g., a `Host` header matching an Ingress), you can configure these using:
    *   `config.well_known_extra_headers`: Adds headers to the request for the `.well-known/openid-configuration` endpoint (if `config.jwks_uri` is *not* set).
    *   `config.jwks_extra_headers`: Adds headers to the request for the JWKS endpoint specified by `config.jwks_uri`.

By using `config.jwks_uri`, you ensure that Kong fetches the JSON Web Key Set directly from the specified internal URL. By adding necessary headers via `config.jwks_extra_headers` or `config.well_known_extra_headers`, you can accommodate internal routing or security requirements.

**Example** configuration using Kong API Gateway 🦍

> [!CAUTION]
> Plugin configuration is **not** helm chart values!

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongClusterPlugin
plugin: unique-jwt-auth
config:
  allowed_iss:
    - https://id.example.com
  jwks_extra_headers:
    forwarded: host=id.example.com
  jwks_uri: http://zitadel.<namespace>.svc.cluster.local:8080/oauth/v2/keys
  uri_param_names:
    - token
  zitadel_project_id: '<ZITADEL_PROJECT_ID>'
  # ssl_verify: false
```

With this configuration, both external clients (e.g., browser users) and the internal JWT validation plugin can utilize the same identity provider (IdP) for token issuance and validation without requiring further customization.

#### Single-use WebSocket tickets (Redis)

Browsers cannot set an `Authorization` header on a WebSocket handshake, so clients often put a credential in the query string. When `ws_ticket_enabled` is true, the plugin can exchange a normal Zitadel JWT for a short-lived opaque ticket and accept that ticket on the upgrade:

1. `POST /auth/ticket` with `Authorization: Bearer <access token>` — plugin verifies the JWT (same checks as the normal path), stores `sha256(ticket)` in Redis with identity + scope + TTL, returns `{ticket, expires_in}`. Never proxied upstream. The access token is never stored.
2. `GET …?ticket=…` with `Upgrade: websocket` — plugin atomically checks scope and retrieves-and-deletes the hash (Redis `EVAL`); a wrong-scope attempt is rejected without consuming the ticket. It then stamps `x-user-id` / `x-company-id`, strips the query parameter, proxies the upgrade.

`?token=` (and cookie / `Authorization`) keep working unchanged. The ticket path is selected only when `?ticket=` is present; there is no fallback to the token path on a bad ticket.

| Setting | Default | Purpose |
| --- | --- | --- |
| `ws_ticket_enabled` | `false` | Master switch. Off = identical to previous behaviour. |
| `ticket_param_name` | `ticket` | Query parameter for the opaque ticket. |
| `ticket_mint_path` | `/auth/ticket` | Path answered by the plugin for minting. |
| `ticket_ttl` | `20` | Ticket lifetime in seconds (5–60). |
| `ticket_scope` | — | Route/service binding written into the record and checked on consume. Required when enabled. |
| `ticket_allowed_origins` | `[]` | Exact Origin allowlist on consume. Empty = not enforced. |
| `ticket_mint_rate_limit` | `60` | Max mints per subject per 60s. `0` disables. |
| `ticket_fail_rate_limit` | `30` | Max failed consumptions per IP per 60s. `0` disables. |
| `redis_host` / `redis_port` | — / `6379` | Redis endpoint reachable from every Kong replica. |
| `redis_password` | — | `referenceable` + `encrypted` (Kong vault). |
| `redis_ssl` / `redis_ssl_verify` | `false` / `true` | TLS to Redis. |
| `redis_timeout_ms` | `2000` | Connect/read timeout. |
| `redis_database` | `7` | Logical Redis DB. Claimed in the monorepo Redis registry (`infrastructure/redis.md`). Redis Cluster has no `SELECT` — set `0` and rely on `redis_key_prefix` for isolation. |
| `redis_key_prefix` | `ws_ticket:` | Key prefix for ticket records and rate-limit counters. |

Redis is required across replicas: `kong.cache` and `lua_shared_dict` are per-pod and cannot enforce single-use. Mint and consume **fail closed** (503) if Redis is unreachable. Pick the logical DB from the monorepo Redis registry; DB `7` is registered for Kong WebSocket tickets.

**Example** (enable per WebSocket route after Redis is provisioned):

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongClusterPlugin
plugin: unique-jwt-auth
config:
  allowed_iss:
    - https://id.example.com
  uri_param_names:
    - token
  zitadel_project_id: '<ZITADEL_PROJECT_ID>'
  ws_ticket_enabled: true
  ticket_scope: ws:graphql
  ticket_allowed_origins:
    - https://app.example.com
  redis_host: redis.kong-system.svc.cluster.local
  redis_port: 6379
  redis_password: '{vault://env/kong-ws-ticket-redis-password}'
```

Rollout: deploy with the flag off (no behaviour change) → provision Redis and enable per tenant → migrate clients from `?token=` to `?ticket=` at their own pace. Redact the ticket query parameter in ingress, WAF, and tracing logs (the plugin strips it from the upstream request only).

## Prometheus Metrics

Both plugins expose a single Prometheus counter for security warning events when Kong's [Prometheus plugin](https://docs.konghq.com/hub/kong-inc/prometheus/) is enabled. Each rejection that produces a `WARN` log increments the counter with a `reason` label that identifies the failure type.

> [!NOTE]
> Kong's Prometheus library automatically prepends `kong_` to every metric name. The value you set in `config.security_warning_metric_name` is the base name — the actual metric exposed is `kong_<name>`.

### unique-jwt-auth

Default metric name: `unique_jwt_auth_security_warnings_total`

Possible `reason` label values:

| reason | description |
|--------|-------------|
| `invalid_signature` | Token signature could not be verified against any known key |
| `multiple_tokens` | More than one token was found in the request |
| `unrecognizable_token_type` | Token is neither a string nor a table |
| `malformed_jwt` | Token could not be decoded as a JWT |
| `disallowed_issuer` | Token `iss` claim does not match `allowed_iss` |
| `unexpected_algorithm` | Token `alg` header does not match configured `algorithm` |
| `claims_validation_failed` | Registered claims (`exp`, `nbf`) failed verification |
| `max_expiration_exceeded` | Token lifetime exceeds `maximum_expiration` |
| `token_expired` | Token `exp` claim indicates expiry |
| `ws_ticket_unknown` | Ticket missing, expired, replayed, or presented outside an upgrade |
| `ws_ticket_scope_mismatch` | Ticket presented on a different route/service than minted for |
| `ws_ticket_origin_rejected` | Upgrade Origin missing or not on the exact allowlist |
| `ws_ticket_mint_rate_limited` | Subject exceeded `ticket_mint_rate_limit` |
| `ws_ticket_redis_error` | Redis unreachable or errored during mint/consume (fail-closed) |

### unique-app-repo-auth

Default metric name: `unique_app_repo_auth_security_warnings_total`

Possible `reason` label values:

| reason | description |
|--------|-------------|
| `api_key_validation_failed` | App repository returned a non-200 response for the API key |
| `multiple_tokens` | More than one token was found in the request |
| `unrecognizable_token_type` | Token is neither a string nor a table |
| `missing_required_headers` | `x-app-id` or `x-company-id` header is absent |

### Example output

```
kong_unique_jwt_auth_security_warnings_total{reason="disallowed_issuer"} 3
kong_unique_jwt_auth_security_warnings_total{reason="invalid_signature"} 1
kong_unique_app_repo_auth_security_warnings_total{reason="api_key_validation_failed"} 12
```

### Overriding the metric name

Set `config.security_warning_metric_name` in the plugin configuration to use a custom base name:

```yaml
config:
  security_warning_metric_name: my_custom_auth_warnings_total
```

The metric will be exposed as `kong_my_custom_auth_warnings_total`.

### Alerts

The chart ships one `PrometheusRule` alert per rejection reason for both plugins — 18 alerts in total — enabled by default when the `monitoring.coreos.com/v1` CRD is present and `prometheus.enabled` is `true`. Each alert fires when total occurrences across gateway pods within a 5-minute window exceed a configurable threshold (`sum(increase(...[5m])) > threshold`). The default threshold is 2 for most alerts and 50 for `KongAppRepoAuthApiKeyValidationFailed` (since individual API key failures are expected).

Expiration-related alerts are **disabled by default** since token expiry is a normal operational event.

#### unique-jwt-auth alerts

| Alert | Reason | Severity | Enabled by default |
|-------|--------|----------|--------------------|
| `KongJwtAuthInvalidSignature` | `invalid_signature` | critical | yes |
| `KongJwtAuthDisallowedIssuer` | `disallowed_issuer` | critical | yes |
| `KongJwtAuthUnexpectedAlgorithm` | `unexpected_algorithm` | critical | yes |
| `KongJwtAuthMalformedJwt` | `malformed_jwt` | warning | yes |
| `KongJwtAuthMultipleTokens` | `multiple_tokens` | warning | yes |
| `KongJwtAuthUnrecognizableTokenType` | `unrecognizable_token_type` | warning | yes |
| `KongJwtAuthClaimsValidationFailed` | `claims_validation_failed` | warning | **no** |
| `KongJwtAuthTokenExpired` | `token_expired` | warning | **no** |
| `KongJwtAuthMaxExpirationExceeded` | `max_expiration_exceeded` | warning | **no** |
| `KongJwtAuthWsTicketUnknown` | `ws_ticket_unknown` | warning | yes |
| `KongJwtAuthWsTicketScopeMismatch` | `ws_ticket_scope_mismatch` | critical | yes |
| `KongJwtAuthWsTicketOriginRejected` | `ws_ticket_origin_rejected` | warning | yes |
| `KongJwtAuthWsTicketMintRateLimited` | `ws_ticket_mint_rate_limited` | warning | yes |
| `KongJwtAuthWsTicketRedisError` | `ws_ticket_redis_error` | critical | yes |

#### unique-app-repo-auth alerts

| Alert | Reason | Severity | Enabled by default |
|-------|--------|----------|--------------------|
| `KongAppRepoAuthApiKeyValidationFailed` | `api_key_validation_failed` | warning | yes |
| `KongAppRepoAuthMultipleTokens` | `multiple_tokens` | warning | yes |
| `KongAppRepoAuthUnrecognizableTokenType` | `unrecognizable_token_type` | warning | yes |
| `KongAppRepoAuthMissingRequiredHeaders` | `missing_required_headers` | warning | yes |

All alert parameters are configured under `prometheus.defaultAlerts.securityWarnings.rules.<AlertName>`:

**Disable an individual alert:**

```yaml
prometheus:
  defaultAlerts:
    securityWarnings:
      rules:
        KongJwtAuthMalformedJwt:
          enabled: false
```

**Enable an expiration alert:**

```yaml
prometheus:
  defaultAlerts:
    securityWarnings:
      rules:
        KongJwtAuthClaimsValidationFailed:
          enabled: true
```

**Override `for`, `severity`, `threshold`, or `interval`:**

```yaml
prometheus:
  defaultAlerts:
    securityWarnings:
      rules:
        KongJwtAuthDisallowedIssuer:
          for: "1m"
          severity: critical
          threshold: 1
          interval: "10m"
```

**Disable all alerts:**

```yaml
prometheus:
  enabled: false
```

**Override metric names** (use this if you set a custom `config.security_warning_metric_name` on the Kong plugin):

```yaml
prometheus:
  defaultAlerts:
    securityWarnings:
      jwtAuthMetricName: kong_my_custom_jwt_warnings_total
      appRepoAuthMetricName: kong_my_custom_app_repo_warnings_total
```

## Upgrading

### To `2.0.0` or `2.1.0` respectively

This release hardens JWT validation in the `unique-jwt-auth` plugin. It includes behavioral changes that may require configuration updates.

#### Breaking: Strict Issuer Matching

Previous versions used Lua pattern matching for `allowed_iss`, which allowed entries like `https://id%.example%.com/.*` to match multiple issuers. Version 2.0.0 requires **exact string matches** only. If your `allowed_iss` entries contain Lua pattern characters (`.`, `%`, `*`, `+`, `?`, `[`, `]`, `^`, `$`, `-`), update them to the literal issuer URL returned in your tokens' `iss` claim.

#### Breaking: TLS Verification Enforced

Requests to OIDC well-known and JWKS endpoints now enforce TLS verification by default. Environments using self-signed certificates or internal CAs not in Kong's trusted store will fail. Ensure the certificate chain for your identity provider is trusted by Kong before upgrading, or set `config.ssl_verify: false` to opt out (e.g., for cluster-internal setups where transport security is handled at the mesh layer).

#### Breaking: JWKS URI Must Be HTTPS

When `config.ssl_verify` is `true` (the default), the `jwks_uri` returned from the well-known endpoint must start with `https://`. Setups using plain `http://` JWKS URIs will be rejected. Set `config.ssl_verify: false` to allow `http://` URIs for cluster-internal IdPs. Note: the HTTPS check applies only to the *discovered* `jwks_uri` from the well-known response, not to `config.jwks_uri` set directly in plugin configuration.

#### Changed Defaults

- `claims_to_verify` now defaults to `["exp", "nbf"]` (previously `["exp"]`). Existing plugin instances keep their persisted config. New installations will validate `nbf` (not-before) by default. If your IdP sets `nbf` to a future timestamp or clock skew is a concern, adjust `claims_to_verify` accordingly.

#### Other Changes

- Unsupported key types (non-RSA) in JWKS responses are skipped instead of causing errors.
- Upstream headers (`X-Unique-*`) are now set only after successful consumer matching.
- Debug logs no longer include full JWT claims or headers.
- Error messages no longer include internal identifiers.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| appRepoAuth | object | `{"appRepositoryUrl":"http://service-app-repository.default.svc:8088","name":"kong-plugin-unique-app-repo-auth"}` | appRepoAuth enables the app-repo-auth plugin |
| appRepoAuth.appRepositoryUrl | string | `"http://service-app-repository.default.svc:8088"` | The default app repository url |
| appRepoAuth.name | string | `"kong-plugin-unique-app-repo-auth"` | The name of the app repository auth config map |
| jwtAuth | object | `{"name":"kong-plugin-unique-jwt-auth"}` | jwtAuth enables the jwt-auth plugin |
| jwtAuth.name | string | `"kong-plugin-unique-jwt-auth"` | The name of the jwt auth config map |
| prometheus.defaultAlerts.securityWarnings | object | `{"additionalLabels":{},"appRepoAuthMetricName":"kong_unique_app_repo_auth_security_warnings_total","enabled":true,"jwtAuthMetricName":"kong_unique_jwt_auth_security_warnings_total","rules":{"KongAppRepoAuthApiKeyValidationFailed":{"enabled":true,"for":"5m","interval":"5m","severity":"warning","threshold":50},"KongAppRepoAuthMissingRequiredHeaders":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":10},"KongAppRepoAuthMultipleTokens":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":2},"KongAppRepoAuthUnrecognizableTokenType":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":10},"KongJwtAuthClaimsValidationFailed":{"enabled":false,"for":"0m","interval":"5m","severity":"warning","threshold":2},"KongJwtAuthDisallowedIssuer":{"enabled":true,"for":"0m","interval":"5m","severity":"critical","threshold":2},"KongJwtAuthInvalidSignature":{"enabled":true,"for":"0m","interval":"5m","severity":"critical","threshold":5},"KongJwtAuthMalformedJwt":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":10},"KongJwtAuthMaxExpirationExceeded":{"enabled":false,"for":"0m","interval":"5m","severity":"warning","threshold":2},"KongJwtAuthMultipleTokens":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":2},"KongJwtAuthTokenExpired":{"enabled":false,"for":"0m","interval":"5m","severity":"warning","threshold":2},"KongJwtAuthUnexpectedAlgorithm":{"enabled":true,"for":"0m","interval":"5m","severity":"critical","threshold":2},"KongJwtAuthUnrecognizableTokenType":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":10},"KongJwtAuthWsTicketMintRateLimited":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":10},"KongJwtAuthWsTicketOriginRejected":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":2},"KongJwtAuthWsTicketRedisError":{"enabled":true,"for":"1m","interval":"5m","severity":"critical","threshold":2},"KongJwtAuthWsTicketScopeMismatch":{"enabled":true,"for":"0m","interval":"5m","severity":"critical","threshold":2},"KongJwtAuthWsTicketUnknown":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":5}}}` | securityWarnings alerts fire on the counters emitted by the kong plugins for each WARN-level security rejection. |
| prometheus.defaultAlerts.securityWarnings.additionalLabels | object | `{}` | Extra labels added to the PrometheusRule metadata and each alert's labels. |
| prometheus.defaultAlerts.securityWarnings.appRepoAuthMetricName | string | `"kong_unique_app_repo_auth_security_warnings_total"` | Base metric name (without kong_ prefix) used in PromQL for the app-repo-auth plugin. Must match config.security_warning_metric_name on the KongClusterPlugin. |
| prometheus.defaultAlerts.securityWarnings.enabled | bool | `true` | Enable the security warnings alert group. Requires monitoring.coreos.com/v1 CRDs. |
| prometheus.defaultAlerts.securityWarnings.jwtAuthMetricName | string | `"kong_unique_jwt_auth_security_warnings_total"` | Base metric name (without kong_ prefix) used in PromQL for the jwt-auth plugin. Must match config.security_warning_metric_name on the KongClusterPlugin. |
| prometheus.defaultAlerts.securityWarnings.rules | object | `{"KongAppRepoAuthApiKeyValidationFailed":{"enabled":true,"for":"5m","interval":"5m","severity":"warning","threshold":50},"KongAppRepoAuthMissingRequiredHeaders":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":10},"KongAppRepoAuthMultipleTokens":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":2},"KongAppRepoAuthUnrecognizableTokenType":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":10},"KongJwtAuthClaimsValidationFailed":{"enabled":false,"for":"0m","interval":"5m","severity":"warning","threshold":2},"KongJwtAuthDisallowedIssuer":{"enabled":true,"for":"0m","interval":"5m","severity":"critical","threshold":2},"KongJwtAuthInvalidSignature":{"enabled":true,"for":"0m","interval":"5m","severity":"critical","threshold":5},"KongJwtAuthMalformedJwt":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":10},"KongJwtAuthMaxExpirationExceeded":{"enabled":false,"for":"0m","interval":"5m","severity":"warning","threshold":2},"KongJwtAuthMultipleTokens":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":2},"KongJwtAuthTokenExpired":{"enabled":false,"for":"0m","interval":"5m","severity":"warning","threshold":2},"KongJwtAuthUnexpectedAlgorithm":{"enabled":true,"for":"0m","interval":"5m","severity":"critical","threshold":2},"KongJwtAuthUnrecognizableTokenType":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":10},"KongJwtAuthWsTicketMintRateLimited":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":10},"KongJwtAuthWsTicketOriginRejected":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":2},"KongJwtAuthWsTicketRedisError":{"enabled":true,"for":"1m","interval":"5m","severity":"critical","threshold":2},"KongJwtAuthWsTicketScopeMismatch":{"enabled":true,"for":"0m","interval":"5m","severity":"critical","threshold":2},"KongJwtAuthWsTicketUnknown":{"enabled":true,"for":"0m","interval":"5m","severity":"warning","threshold":5}}` | Per-alert configuration. Each entry controls enabled, severity, for, threshold (number of occurrences in interval), and interval (PromQL range window). |
| prometheus.enabled | bool | `true` | Enable Prometheus integration. When false no PrometheusRule resources are rendered. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
