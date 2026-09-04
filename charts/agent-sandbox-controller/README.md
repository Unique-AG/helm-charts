# agent-sandbox-controller

Helm chart for the Agent Sandbox controller — a Kubernetes CRD and controller for managing isolated, stateful, singleton workloads (e.g. AI agent runtimes).

Upstream project: https://github.com/kubernetes-sigs/agent-sandbox

![Version: 0.5.6](https://img.shields.io/badge/Version-0.5.6-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v0.5.6](https://img.shields.io/badge/AppVersion-v0.5.6-informational?style=flat-square)

## Installation

Releases are published as OCI artifacts to GHCR.

```sh
helm install my-agent-sandbox-controller oci://ghcr.io/unique-ag/helm-charts/agent-sandbox-controller --version 0.5.6
```

## Implementation Details

This chart packages the upstream [`kubernetes-sigs/agent-sandbox`](https://github.com/kubernetes-sigs/agent-sandbox) controller. It deploys:

- The controller `Deployment` with leader election enabled by default.
- The `ClusterRole`/`ClusterRoleBinding` and `ServiceAccount` required by the controller.
- An optional extensions controller (`SandboxClaim`, `SandboxTemplate`, `SandboxWarmPool`) toggled via `extensions.enabled`.
- The sandbox `router` deployment, service, and `NetworkPolicy` toggled via `router.enabled`.
- A conversion webhook `Service` (port 443 → 9443) plus namespaced Role/RoleBinding for the self-signed webhook cert Secret. Required by the multi-version CRDs.
- The `Sandbox` and extensions CRDs (installed via Helm's `crds/` mechanism, not templated).

### CRDs

CRDs in `crds/` are installed by Helm on `helm install` but are **not** upgraded or deleted by Helm. To pick up CRD changes on upgrade you must apply them manually (Server-Side Apply recommended), from a checkout of this repository:

```sh
kubectl apply --server-side --force-conflicts -f charts/agent-sandbox-controller/crds/
```

The bundled CRDs ship with `conversion.strategy=Webhook` and a placeholder `clientConfig` pointing at `agent-sandbox-webhook-service` in `agent-sandbox-system`. The controller patches `caBundle` plus the Service name/namespace onto those CRDs at startup (`--manage-webhook-certs=true`, `--webhook-namespace=<release namespace>`). Unique deploys this chart into `system`, so the patched webhook Service is `agent-sandbox-webhook-service.system`.

### Upgrading from v0.4.x (v1alpha1 → v1beta1)

This is a **breaking** upgrade. Read the upstream [API Migration Guide](https://agent-sandbox.sigs.k8s.io/docs/getting_started/api-migration-guide/) before applying. In short:

1. Turn Argo auto-sync **off** for the controller and every `SandboxTemplate` / `SandboxWarmPool` app.
2. Run `files/migrate.sh --phase=bootstrap` **before** applying the new CRDs. This pre-creates `shadow-pool-<template>` warm pools for any cold-start `v1alpha1` SandboxClaims. Skip this only if you have confirmed there are no live claims.
3. Apply the new CRDs (SSA) then sync the controller chart. Wait until the controller is Ready **and** `kubectl get sandboxwarmpools.extensions.agents.x-k8s.io` succeeds (webhook is serving).
4. Run `files/migrate.sh --phase=migrate` to rewrite etcd storage to `v1beta1`.
5. Update SandboxTemplate/SandboxWarmPool manifests to `apiVersion: extensions.agents.x-k8s.io/v1beta1`, and SandboxClaims from `spec.sandboxTemplateRef` to `spec.warmPoolRef.name`.

Upgrade directly to **v0.5.6** (or at least v0.5.2). Do not stop on v0.5.0/v0.5.1 — those have a status-wiping race on warm-started claims.

`files/migrate.sh` is the upstream helper vendored from `kubernetes-sigs/agent-sandbox` v0.5.6.

### SDK Integration

The Python SDK tunnel mode auto-discovers a service named `sandbox-router-svc`. To opt in, set `router.service.name: sandbox-router-svc` so the router service name matches the SDK default.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for the controller pod. |
| controller | object | `{"extraArgs":[],"sandboxWarmPoolReadinessGracePeriod":"","sandboxWarmPoolUnschedulableRecheckInterval":""}` | Optional extra controller flags. Unset values are omitted from the container args. |
| controller.extraArgs | list | `[]` | Additional flags not listed above (e.g. zap logging flags). |
| controller.sandboxWarmPoolReadinessGracePeriod | string | `""` | How long a warm pool sandbox may stay non-Ready before it is considered stuck (extensions only). Controller default is `5m`. |
| controller.sandboxWarmPoolUnschedulableRecheckInterval | string | `""` | Re-check interval for pools holding unschedulable sandboxes past the grace period (extensions only). Controller default is `1m`. |
| extensions | object | `{"enabled":true}` | Enable the upstream sandbox extensions controller (`SandboxClaim`, `SandboxTemplate`, `SandboxWarmPool`). |
| extensions.enabled | bool | `true` | Toggle the extensions controller and its RBAC. |
| fullnameOverride | string | `""` | This is to override the full name. |
| image | object | `{"digest":"sha256:dc23fb0d5624c306ca2f8ef0d41848dba670ebaf62beb500f870175aec529ffd","pullPolicy":"IfNotPresent","repository":"registry.k8s.io/agent-sandbox/agent-sandbox-controller","tag":""}` | Container image used by the controller. |
| image.digest | string | `"sha256:dc23fb0d5624c306ca2f8ef0d41848dba670ebaf62beb500f870175aec529ffd"` | Pin a specific image by digest. Recommended for supply-chain integrity. |
| image.pullPolicy | string | `"IfNotPresent"` | This sets the pull policy for images. |
| image.repository | string | `"registry.k8s.io/agent-sandbox/agent-sandbox-controller"` | This sets the image repository. |
| image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
| imagePullSecrets | list | `[]` | Image pull secrets for the controller pod. |
| leaderElect | bool | `true` | Enable controller leader election (`--leader-elect=true`). |
| metrics | object | `{"prometheusRule":{"additionalGroups":[],"additionalLabels":{},"enabled":false},"serviceMonitor":{"additionalLabels":{},"enabled":false,"interval":"30s","scrapeTimeout":""}}` | Prometheus Operator scrape and alerting resources for the controller metrics endpoint. |
| metrics.prometheusRule.additionalGroups | list | `[]` | Additional Prometheus rule groups appended after the chart's starter group. |
| metrics.prometheusRule.additionalLabels | object | `{}` | Extra labels (often required to match Prometheus `ruleSelector`). |
| metrics.prometheusRule.enabled | bool | `false` | Create a starter `PrometheusRule`. Requires the prometheus-operator CRDs. |
| metrics.serviceMonitor.additionalLabels | object | `{}` | Extra labels (often required to match Prometheus `serviceMonitorSelector`). |
| metrics.serviceMonitor.enabled | bool | `false` | Create a `ServiceMonitor` for `/metrics`. Requires the prometheus-operator CRDs. |
| metrics.serviceMonitor.interval | string | `"30s"` | Scrape interval. |
| metrics.serviceMonitor.scrapeTimeout | string | `""` | Scrape timeout. Omitted unless set. |
| nameOverride | string | `""` | This is to override the release name. |
| nodeSelector | object | `{}` | Node selector for the controller pod. |
| podAnnotations | object | `{}` | Extra annotations added to the controller pod template. |
| podLabels | object | `{}` | Extra labels added to the controller pod template (selector labels win on conflict). |
| podSecurityContext | object | `{"fsGroup":65532,"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context applied to the controller pod. |
| replicaCount | int | `1` | Number of controller replicas. Leader election is used to elect a single active leader. |
| resources | object | `{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}` | Controller container resource requests and limits. |
| router | object | `{"auth":{"allowUnauthenticated":false,"existingSecret":"","secretKey":"token"},"containerPort":8080,"containerSecurityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000},"enabled":true,"image":{"digest":"sha256:b66415363649ed14e68efbeac02a79681461834c265c9a20867a6ac60c21a74e","pullPolicy":"IfNotPresent","repository":"us-central1-docker.pkg.dev/k8s-staging-images/agent-sandbox/sandbox-router","tag":"v20260820-v0.5.6"},"livenessProbe":{"initialDelaySeconds":10,"path":"/healthz","periodSeconds":10},"networkPolicy":{"egress":{"sandboxNamespaceSelector":{},"sandboxPort":8888},"enabled":true,"ingress":{"allowedCIDRs":[],"allowedSources":[]}},"podSecurityContext":{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"proxyTimeoutSeconds":180,"readinessProbe":{"initialDelaySeconds":5,"path":"/healthz","periodSeconds":5},"replicaCount":2,"resources":{"limits":{"cpu":"250m","memory":"512Mi"},"requests":{"cpu":"250m","memory":"512Mi"}},"service":{"name":"","port":8080,"type":"ClusterIP"},"topologySpreadConstraints":{"enabled":true,"maxSkew":1,"topologyKey":"topology.kubernetes.io/zone","whenUnsatisfiable":"ScheduleAnyway"}}` | Sandbox router subchart configuration. The router proxies traffic to sandbox pods and is required for the Python SDK tunnel mode. |
| router.auth | object | `{"allowUnauthenticated":false,"existingSecret":"","secretKey":"token"}` | Router request authentication. The router refuses to start without a token unless unauthenticated mode is explicitly allowed. |
| router.auth.allowUnauthenticated | bool | `false` | Run the router without authentication (`ALLOW_UNAUTHENTICATED_ROUTER=true`). Ignored when `existingSecret` is set. |
| router.auth.existingSecret | string | `""` | Name of an existing Secret holding the router auth token (`ROUTER_AUTH_TOKEN`). |
| router.auth.secretKey | string | `"token"` | Key in the Secret that holds the token. |
| router.containerPort | int | `8080` | Container port the router listens on inside the pod. |
| router.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000}` | Container-level security context applied to the router container. |
| router.enabled | bool | `true` | Toggle the sandbox router deployment, service, and network policy. |
| router.image | object | `{"digest":"sha256:b66415363649ed14e68efbeac02a79681461834c265c9a20867a6ac60c21a74e","pullPolicy":"IfNotPresent","repository":"us-central1-docker.pkg.dev/k8s-staging-images/agent-sandbox/sandbox-router","tag":"v20260820-v0.5.6"}` | Container image used by the router. |
| router.image.digest | string | `"sha256:b66415363649ed14e68efbeac02a79681461834c265c9a20867a6ac60c21a74e"` | Pin a specific router image by digest. |
| router.image.pullPolicy | string | `"IfNotPresent"` | This sets the pull policy for the router image. |
| router.image.repository | string | `"us-central1-docker.pkg.dev/k8s-staging-images/agent-sandbox/sandbox-router"` | This sets the router image repository. |
| router.image.tag | string | `"v20260820-v0.5.6"` | Overrides the router image tag. |
| router.livenessProbe | object | `{"initialDelaySeconds":10,"path":"/healthz","periodSeconds":10}` | HTTP liveness probe configuration for the router. |
| router.networkPolicy | object | `{"egress":{"sandboxNamespaceSelector":{},"sandboxPort":8888},"enabled":true,"ingress":{"allowedCIDRs":[],"allowedSources":[]}}` | `NetworkPolicy` for the router pod. |
| router.networkPolicy.egress | object | `{"sandboxNamespaceSelector":{},"sandboxPort":8888}` | Egress rules. By default the router needs to reach DNS and sandbox pods. |
| router.networkPolicy.egress.sandboxNamespaceSelector | object | `{}` | Namespace selector matching the namespace where sandboxes run. When unset the release namespace is used (`kubernetes.io/metadata.name: <release namespace>`). |
| router.networkPolicy.egress.sandboxPort | int | `8888` | Port the router uses to reach sandbox pods. |
| router.networkPolicy.enabled | bool | `true` | Render the `NetworkPolicy` for the router. |
| router.networkPolicy.ingress | object | `{"allowedCIDRs":[],"allowedSources":[]}` | Ingress rules. When both `allowedSources` and `allowedCIDRs` are empty no ingress rule is rendered. |
| router.networkPolicy.ingress.allowedCIDRs | list | `[]` | List of CIDRs allowed to reach the router (e.g. `10.0.0.0/8`). |
| router.networkPolicy.ingress.allowedSources | list | `[]` | List of `{ podSelector, namespaceSelector }` pairs allowed to reach the router. |
| router.podSecurityContext | object | `{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context applied to the router pod. |
| router.proxyTimeoutSeconds | int | `180` | Upstream proxy timeout in seconds the router applies when forwarding to sandboxes. |
| router.readinessProbe | object | `{"initialDelaySeconds":5,"path":"/healthz","periodSeconds":5}` | HTTP readiness probe configuration for the router. |
| router.replicaCount | int | `2` | Number of router replicas. |
| router.resources | object | `{"limits":{"cpu":"250m","memory":"512Mi"},"requests":{"cpu":"250m","memory":"512Mi"}}` | Router container resource requests and limits. |
| router.service | object | `{"name":"","port":8080,"type":"ClusterIP"}` | Router `Service` settings. |
| router.service.name | string | `""` | Override the router service name. Defaults to `<release>-agent-sandbox-controller-router-svc`. The Python SDK tunnel mode auto-discovers `sandbox-router-svc` by default, so set this to `sandbox-router-svc` for seamless SDK integration. |
| router.service.port | int | `8080` | Service port exposed by the router. |
| router.service.type | string | `"ClusterIP"` | Service type for the router. |
| router.topologySpreadConstraints | object | `{"enabled":true,"maxSkew":1,"topologyKey":"topology.kubernetes.io/zone","whenUnsatisfiable":"ScheduleAnyway"}` | Spread router replicas across topology domains (defaults to zones). |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532}` | Container-level security context applied to the controller container. |
| service | object | `{"port":8080}` | Controller `Service` settings. |
| service.port | int | `8080` | Service port exposing controller metrics. |
| tolerations | list | `[]` | Tolerations for the controller pod. |
| webhook | object | `{"enabled":true,"serviceName":"agent-sandbox-webhook-service"}` | Conversion webhook used by the multi-version CRDs (`v1alpha1` <-> `v1beta1`). Stock upstream CRDs use `conversion.strategy=Webhook` and must have a live webhook. |
| webhook.enabled | bool | `true` | Toggle the webhook server, Service, and cert Secret RBAC. Disable only if CRDs are rewritten to `conversion.strategy=None`. |
| webhook.serviceName | string | `"agent-sandbox-webhook-service"` | Name of the conversion webhook Service. Must match the name the controller patches onto CRD `clientConfig`. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
