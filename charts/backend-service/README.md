# backend-service

The 'backend-service' chart is a "convenience" chart from Unique AG that can generically be used to deploy backend workloads to Kubernetes.

Note that this chart assumes that you have a valid contract with Unique AG and thus access to the required Docker images.

![Version: 10.1.1](https://img.shields.io/badge/Version-10.1.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: latest](https://img.shields.io/badge/AppVersion-latest-informational?style=flat-square)

## Implementation Details

### OCI Availability
```sh
# Helm Repository
helm repo add unique https://unique-ag.github.io/helm-charts/
helm install my-backend-service unique/backend-service --version 10.1.1

# OCI
helm install my-backend-service oci://ghcr.io/unique-ag/helm-charts/backend-service --version 10.1.1
```

### Docker Images
The chart uses [`ghcr.io/unique-ag/chart-testing-service`](https://github.com/Unique-AG/helm-charts/pkgs/container/chart-testing-service) as its default image for CI testing. Replace with actual Unique images when deploying.

### Networking
The chart supports [Gateway API](https://gateway-api.sigs.k8s.io) resources (recommended). Enable specific `routes` or use `extraRoutes` to configure them. See [Routes](#routes).

### Ports
<small>added in `3.1.0`</small>

```yaml
ports:
  application: 8080  # container port
  service: 80        # service port (service.port takes precedence if set)
```

Simplifies inter-service communication by using standard ports:
```yaml
# before
ANOTHER_SERVICE_URL: http://backend-service.namespace.svc:8080

# after
ANOTHER_SERVICE_URL: http://backend-service.namespace.svc
```

#### Routes
<small>added in `2.0.0`</small>

Supports [Gateway API route resources](https://gateway-api.sigs.k8s.io/concepts/api-overview/#route-resources). Use `routes` for simplified configuration or `extraRoutes` for full control.

**Requirements:** [Gateway API CRDs](https://gateway-api.sigs.k8s.io/guides/#getting-started-with-gateway-api) must be installed in at least `1.3.0`.

**HTTPS Redirects:** Not enabled by default. Handle in upstream services or via `extraAnnotations`.

**Timeouts:** HTTPRoute timeouts are supported via `routes.timeout` or per-path `routes.paths.<name>.timeout`. The value sets both `request` and `backendRequest` timeouts (GEP-2257). Note: Kubernetes Service annotations (e.g., `konghq.com/read-timeout`) take precedence over HTTPRoute timeouts in KIC's translation pipeline and it is not recommended to set both values. Preferred is the Gateway APIs `timeout(s)`.

### Network Policies
<small>added in `4.4.0`</small>

Two flavors supported:

- **`kubernetes`** (default): Standard Kubernetes NetworkPolicy resources
- **`cilium`**: Cilium's CiliumNetworkPolicy resources with enhanced features

```yaml
networkPolicy:
  enabled: true
  flavor: kubernetes  # or "cilium"
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels: { name: monitoring }
      ports:
        - { protocol: TCP, port: 8080 }
  egress:
    - to:
        - namespaceSelector:
            matchLabels: { name: database }
      ports:
        - { protocol: TCP, port: 5432 }
```

| Flavor | API Version | Selector |
|--------|-------------|----------|
| `kubernetes` (default) | `networking.k8s.io/v1` | `podSelector` |
| `cilium` | `cilium.io/v2` | `endpointSelector` |

**Notes:**
- Requires a CNI that supports NetworkPolicy (Calico, Cilium, Weave Net)
- Include DNS (port 53/UDP) in egress rules if pods need hostname resolution

Examples: [`ci/networkpolicy-values.yaml`](https://github.com/Unique-AG/helm-charts/blob/main/charts/backend-service/ci/networkpolicy-values.yaml), [`ci/networkpolicy-cilium-values.yaml`](https://github.com/Unique-AG/helm-charts/blob/main/charts/backend-service/ci/networkpolicy-cilium-values.yaml)

### CronJobs
Deploy cron jobs alongside the main deployment, sharing environment settings and image. Use for workload-related jobs only.

Example: [`ci/cronjobs-values.yaml`](https://github.com/Unique-AG/helm-charts/blob/main/charts/backend-service/ci/cronjobs-values.yaml)

### Audit Volumes
<small>added in `9.0.0`</small>

Cloud-agnostic audit log storage with blue-green migration support.

```yaml
auditVolumes:
  target: blue  # or "/dev/stdout"
  volumes:
    blue:
      enabled: true
      capacity: 1Ti
      azure:
        resourceGroup: my-rg
        storageAccount: mystorageaccount
        containerName: audit-logs
```

#### Key Concepts

| Field | Description |
|-------|-------------|
| `target` | Where audit logs go. Can be a volume key (`blue`) or direct path (`/dev/stdout`) |
| `volumes` | Map of named volumes. Each creates a PV/PVC pair named `{fullname}-audit-{key}` |
| `azure` | Azure Blob NFS config. Presence of this field enables Azure provider |
| `name` | Optional explicit PV/PVC name for backward compatibility |
| `mountPath` | Optional, defaults to `/audit-{key}` |

#### AUDIT_LOG_DIR Environment Variable

The `AUDIT_LOG_DIR` environment variable is automatically set based on `auditVolumes.target`:

| `target` value | Condition | `AUDIT_LOG_DIR` value |
|----------------|-----------|----------------------|
| Volume key (e.g., `blue`) | Volume `enabled: true` + cloud provider configured | Volume's `mountPath` (or `/audit-{key}` if not set) |
| Volume key (e.g., `blue`) | Volume missing, disabled, or no cloud provider | **Not set** (env var omitted) |
| Direct path (e.g., `/dev/stdout`) | Always | The path directly (e.g., `/dev/stdout`) |
| Not specified | Always | **Not set** (env var omitted) |

> ⚠️ A volume requires both `enabled: true` **and** a cloud provider configuration (e.g., `azure`) to be created. Without a cloud provider, no PV/PVC is created and `AUDIT_LOG_DIR` is not set.

#### Blue-Green Migration

1. Add new volume (`green`) → 2. Deploy (both mounted) → 3. Migrate data → 4. Switch target → 5. Disable old

```yaml
auditVolumes:
  target: green
  volumes:
    blue: { enabled: true, name: my-release-audit, azure: { resourceGroup: old-rg, storageAccount: oldaccount } }
    green: { enabled: true, azure: { resourceGroup: new-rg, storageAccount: newaccount } }
```

#### Stdout Logging

```yaml
auditVolumes:
  target: /dev/stdout  # No PV/PVC created
```

### Environment Variables

| Source | Type | Description |
|--------|------|-------------|
| `env` | `map` | Flat key-value pairs, creates internal ConfigMap |
| `envVars` | `list` | Full Kubernetes env syntax (supports `valueFrom`) |
| `extraEnvCM` | `list` | Names of existing ConfigMaps |
| `extraEnvSecrets` | `list` | Names of existing Secrets |
| `secretProvider` | `map` | Azure Key Vault secrets via CSI driver |

#### Precedence Order

Environment variables are loaded in a specific order. **Later sources override earlier sources** when the same variable name is defined.

##### Deployment

```
envFrom (loaded first, lower precedence):
  1. ConfigMap (contains: env + VERSION + PORT)
  2. extraEnvCM
  3. extraEnvSecrets

env (loaded last, higher precedence):
  4. envVars
  5. secretProvider
  6. auditVolumes (AUDIT_LOG_DIR)
  7. workloadIdentity.gcp (GOOGLE_APPLICATION_CREDENTIALS)
```

##### cronJobs

```
envFrom:
  1. extraEnvCM
  2. extraEnvSecrets

env:
  3. envVars (global, deduplicated with local envVars)
  4. Merged env (global env + cronJobs.<name>.env, local takes precedence)
  5. cronJobs.<name>.envVars (local)
  6. auditVolumes (AUDIT_LOG_DIR) - protected
  7. VERSION (auto-set) - protected
  8. secretProvider
```

Global `envVars` entries are excluded if the same name exists in local `envVars`.

##### Hooks

```
envFrom:
  1. ConfigMap (contains: env + VERSION)
  2. extraEnvCM
  3. extraEnvSecrets

env:
  4. envVars (global, deduplicated with per-hook envVars)
  5. Merged env (global env + hooks.<name>.env, per-hook takes precedence)
  6. hooks.<name>.envVars (per-hook)
  7. VERSION (auto-set) - protected
  8. workloadIdentity.gcp (GOOGLE_APPLICATION_CREDENTIALS)
  9. secretProvider
```

Global `envVars` entries are excluded if the same name exists in per-hook `envVars`.

#### Example: Overriding Variables

```yaml
env:
  DATABASE_URL: "postgres://global:5432/db"

cronJobs:
  cleanup:
    schedule: "0 0 * * *"
    env:
      DATABASE_URL: "postgres://readonly:5432/db"  # takes precedence

envVars:
  - name: DATABASE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-secret
        key: password
```

#### Protected Variables

The following variables are automatically set and cannot be overridden via `env`:
- `VERSION` - Set to the image tag
- `PORT` - Set to the application port (deployment only)

To override these, use `envVars` which has higher precedence.

## JSON Schema

Schema available in `values.schema.json` for validation and IDE autocompletion.

## Azure Key Vault Access

Supports VM Managed Identity via `secretProvider`:
- [System-assigned Managed Identity](https://azure.github.io/secrets-store-csi-driver-provider-azure/docs/configurations/identity-access-modes/system-assigned-msi-mode/)
- [User-assigned Managed Identity](https://azure.github.io/secrets-store-csi-driver-provider-azure/docs/configurations/identity-access-modes/user-assigned-msi-mode/)

Other methods (service principals, pod identity) not supported. Use `extraObjects` for custom setups. Workload Identity: [open an issue](https://github.com/Unique-AG/helm-charts/issues) if needed.

## Upgrade Guides

### ~> `10.0.1`

> Version `10.0.0` shall be skipped as it introduced an error-prone rename that was reverted for `10.0.1`.

<details>
<summary>🤖 LLM Migration Prompt</summary>

```text
Migrate my backend-service Helm values from 9.x to 10.x:

1. `cronJob` + `extraCronJobs` → `cronJobs`: Merge both into a single `cronJobs` map.
   For `cronJob`: name becomes the key, move `jobTemplate.restartPolicy` to top-level,
   remove `jobTemplate.containers.name`. For `extraCronJobs`: move entries directly into `cronJobs`.

2. `envSecrets` → `envVars`: Replace with `extraEnvSecrets` ref or `envVars` with `secretKeyRef`.

3. envFrom order changed: now `extraEnvCM` → `extraEnvSecrets` (secrets take precedence).
```

</details>

**Breaking changes:**

| Change | Migration |
|--------|-----------|
| `cronJob` removed | Use `cronJobs` map syntax |
| `extraCronJobs` removed | Merge into `cronJobs` map |
| `envSecrets` removed | Use `extraEnvSecrets` or `envVars` with `secretKeyRef` |
| `cronJobs` envFrom order | Now `extraEnvCM` → `extraEnvSecrets` (secrets take precedence) |
| `VERSION` protected in hooks | Cannot be overridden via env values |

**Fixes:** `cronJobs` duplicate envVars bug, env merging (local takes precedence)

**New:** Per-hook `env` and `envVars` support (`hooks.<name>.env`, `hooks.<name>.envVars`)

**Migration examples:**

`cronJob` → `cronJobs`:
```yaml
cronJob:
  enabled: true
  name: my-cronjob
  schedule: "0 0 * * *"
  concurrencyPolicy: Forbid
  failedJobsHistoryLimit: 3
  successfulJobsHistoryLimit: 3
  startingDeadlineSeconds: 60
  suspend: false
  timeZone: Europe/Zurich
  jobTemplate:
    containers:
      name: my-container
    restartPolicy: OnFailure
  env:
    MY_VAR: value
  envVars:
    - name: SECRET_VAR
      valueFrom:
        secretKeyRef:
          name: my-secret
          key: password
```

To:
```yaml
cronJobs:
  my-cronjob:  # name becomes the key
    schedule: "0 0 * * *"
    restartPolicy: OnFailure  # moved from jobTemplate
    env:
      MY_VAR: value
    envVars:
      - name: SECRET_VAR
        valueFrom:
          secretKeyRef:
            name: my-secret
            key: password
```

`extraCronJobs` → `cronJobs` (merge into map):
```yaml
# Before
extraCronJobs:
  my-extra-job:
    schedule: "0 * * * *"
    restartPolicy: OnFailure
    env:
      MODE: extra

# After (merge into cronJobs)
cronJobs:
  my-extra-job:
    schedule: "0 * * * *"
    restartPolicy: OnFailure
    env:
      MODE: extra
```

`envSecrets` → `envVars`:
```yaml
# Before (insecure)                   # After
envSecrets:                           envVars:
  DB_PASS: "secret123"                  - name: DB_PASS
                                          valueFrom:
                                            secretKeyRef:
                                              name: my-secret
                                              key: password
```

### ~> `9.0.0`

**Breaking change:** `auditVolume` → `auditVolumes` (cloud-agnostic, blue-green ready). See [Audit Volumes](#audit-volumes).

From:
```yaml
auditVolume:
  enabled: true
  mountPath: /audit
  capacity: 1Ti
  attributes:
    resourceGroup: my-resource-group
    storageAccount: mystorageaccount
    containerName: audit-logs
```

To:
```yaml
auditVolumes:
  target: blue
  volumes:
    blue:
      enabled: true
      capacity: 1Ti
      azure:
        resourceGroup: my-resource-group
        storageAccount: mystorageaccount
        containerName: audit-logs
```

### ~> `8.0.0`

**Breaking change:** `serviceAccount.workloadIdentity` → `workloadIdentity.azure`

From:
```yaml
serviceAccount:
  workloadIdentity:
    enabled: true
    clientId: "..."
```

To:
```yaml
workloadIdentity:
  azure:
    enabled: true
    clientId: "..."
```

### ~> `7.0.0`

**Breaking changes:** Pod identity and external-secrets removed.

Pod identity users: migrate to `secretProvider` with VM Managed Identity. External-secrets users: use `extraObjects` or manage secrets outside the chart.

### ~> `6.0.0`

**Breaking change:** KEDA `scalers` list → `triggers` map for better overlay support.

From:
```yaml
keda:
  enabled: true
  scalers:
    - type: rabbitmq
      metadata:
        protocol: amqp
        queueName: testqueue
        mode: QueueLength
        value: "20"
      authenticationRef:
        name: keda-trigger-auth-rabbitmq-conn
    - type: cron
      metadata:
        timezone: Europe/Zurich
        start: 0 6 * * *
        end: 0 20 * * *
        desiredReplicas: "10"
```

To:
```yaml
keda:
  enabled: true
  triggers:
    rabbitmq-trigger:
      type: rabbitmq
      metadata:
        protocol: amqp
        queueName: testqueue
        mode: QueueLength
        value: "20"
      authenticationRef:
        name: keda-trigger-auth-rabbitmq-conn
    cron-trigger:
      type: cron
      metadata:
        timezone: Europe/Zurich
        start: 0 6 * * *
        end: 0 20 * * *
        desiredReplicas: "10"
```

### ~> `5.0.0`

**Breaking changes:**
- `eventBasedAutoscaling` → `keda`
- `routes.paths.default.enabled: false` to disable default route
- Tyk resources removed (use Kong)
- `prometheus.rules` → `defaultAlerts` + `additionalAlerts`

**Alerts migration:**

**From:**
```yaml
prometheus:
  enabled: true
  team: backend-team
  rules:
    QNodeChat5xx:
      expression: >
        sum(
          max_over_time(
            nestjs_http_server_responses_total{status=~"^5..$", app="node_chat"}[1m]
          )
          or
          vector(0)
        )
          by (app, path, method, status)
        -
        sum(
          max_over_time(
            nestjs_http_server_responses_total{status=~"^5..$", app="node_chat"}[1m]
            offset 1m
          )
          or vector(0)
        )
          by (app, path, method, status)
        > 0
      for: 0m
      severity: critical
      labels:
        app: app
```

To:
```yaml
prometheus:
  enabled: true
  defaultAlerts:
    additionalLabels:
      team: backend-team
      app: app
  additionalAlerts:
    QNodeChat5xx:
      alert: QNodeChat5xx
      expr: >
        sum(max_over_time(nestjs_http_server_responses_total{status=~"^5..$", app="node_chat"}[1m]) or vector(0)) by (app, path, method, status)
        - sum(max_over_time(nestjs_http_server_responses_total{status=~"^5..$", app="node_chat"}[1m] offset 1m) or vector(0)) by (app, path, method, status)
        > 0
      for: 0m
      labels:
        severity: critical
        alertGroup: application
```

### ~> `3.0.0`

- `routes` keys: `lower_snake_case` → `camelCase`
- `routes.paths.up` → `routes.paths.probe`

### ~> `2.0.0`

- `httproute` → `extraRoutes` (dictionary)
- `ingress` removed (use Gateway API)

## Development

Local templating requires `--api-versions` for Gateway API resources:
```sh
helm template some-app oci://ghcr.io/unique-ag/helm-charts/backend-service --api-versions gateway.networking.k8s.io/v1 --values your-own-values.yaml
```

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
