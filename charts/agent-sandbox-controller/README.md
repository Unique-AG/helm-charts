# agent-sandbox-controller

Helm chart for the Agent Sandbox controller — a Kubernetes CRD and controller for managing isolated, stateful, singleton workloads (e.g. AI agent runtimes).

Upstream project: https://github.com/kubernetes-sigs/agent-sandbox

![Version: 1.0.1](https://img.shields.io/badge/Version-1.0.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v1.0.1](https://img.shields.io/badge/AppVersion-v1.0.1-informational?style=flat-square)

## Installation

Releases are published as OCI artifacts to GHCR.

```sh
helm install my-agent-sandbox-controller oci://ghcr.io/unique-ag/helm-charts/agent-sandbox-controller --version 1.0.1
```

## Implementation Details

This chart packages the upstream [`kubernetes-sigs/agent-sandbox`](https://github.com/kubernetes-sigs/agent-sandbox) controller. It deploys:

- The controller `Deployment` with leader election enabled by default.
- The `ClusterRole`/`ClusterRoleBinding` and `ServiceAccount` required by the controller.
- An optional extensions controller (`SandboxClaim`, `SandboxTemplate`, `SandboxWarmPool`) toggled via `extensions.enabled`.
- The Go sandbox `router` deployment, service, and `NetworkPolicy` toggled via `router.enabled`. The optional Pod-IP cache (`router.cache.enabled`) adds a router ServiceAccount and cluster-wide pod read RBAC.
- The `Sandbox` and extensions CRDs (installed via Helm's `crds/` mechanism, not templated).

The controller mounts the optional `agent-sandbox-config` ConfigMap at `/etc/sandbox-config`; create it to configure the `SandboxClaim.spec.additionalPodMetadata.labels` allowlist.

### CRDs

CRDs in `crds/` are installed by Helm on `helm install` but are **not** upgraded or deleted by Helm. To pick up CRD changes on upgrade you must apply them manually (Server-Side Apply recommended), from a checkout of this repository:

```sh
kubectl apply --server-side --force-conflicts -f charts/agent-sandbox-controller/crds/
```

### Upgrading to 1.x (v1alpha1 removal)

Upstream v1.0.0 removes the `v1alpha1` API and the conversion webhook. Direct upgrades from chart 0.4.x are **not supported** — the API server rejects CRDs that drop a version still listed in `status.storedVersions`. Read the upstream [API Migration Guide](https://agent-sandbox.sigs.k8s.io/docs/getting_started/api-migration-guide/) before applying.

1. Upgrade to chart **0.5.6** first and complete its `v1alpha1` → `v1beta1` storage migration (that version's README documents the `migrate.sh` procedure).
2. Verify every CRD stores only `v1beta1`:

   ```sh
   kubectl get crd sandboxes.agents.x-k8s.io \
     sandboxclaims.extensions.agents.x-k8s.io \
     sandboxtemplates.extensions.agents.x-k8s.io \
     sandboxwarmpools.extensions.agents.x-k8s.io \
     -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.storedVersions}{"\n"}{end}'
   ```

3. Apply the new CRDs (SSA, see above), then upgrade the chart.
4. Delete the webhook cert Secret the old controller created outside of Helm:

   ```sh
   kubectl delete secret agent-sandbox-webhook-certs -n <release namespace> --ignore-not-found
   ```

The webhook Service and cert Role/RoleBinding were Helm-managed and are removed by the upgrade itself.

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
| image | object | `{"digest":"sha256:e1787f95cda406e2d81322e8637b6dfa2d77514fbbd0536a872b8e5d409b7154","pullPolicy":"IfNotPresent","repository":"registry.k8s.io/agent-sandbox/agent-sandbox-controller","tag":""}` | Container image used by the controller. |
| image.digest | string | `"sha256:e1787f95cda406e2d81322e8637b6dfa2d77514fbbd0536a872b8e5d409b7154"` | Pin a specific image by digest. Recommended for supply-chain integrity. |
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
| router | object | `{"cache":{"enabled":false},"containerPort":8080,"containerSecurityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000},"enabled":true,"extraArgs":[],"image":{"digest":"sha256:25b1a09396306eb056ea5b81d6b5ac96ae685e785eb45c84b6416e7d7fac938e","pullPolicy":"IfNotPresent","repository":"registry.k8s.io/agent-sandbox/sandbox-router-go","tag":""},"livenessProbe":{"initialDelaySeconds":5,"path":"/healthz","periodSeconds":10},"networkPolicy":{"egress":{"sandboxNamespaceSelector":{},"sandboxPort":8888},"enabled":true,"ingress":{"allowedCIDRs":[],"allowedSources":[]}},"podSecurityContext":{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"proxyTimeoutSeconds":180,"readinessProbe":{"initialDelaySeconds":1,"path":"/readyz","periodSeconds":5},"replicaCount":2,"resources":{"limits":{"cpu":"250m","memory":"512Mi"},"requests":{"cpu":"250m","memory":"512Mi"}},"service":{"name":"","port":8080,"type":"ClusterIP"},"topologySpreadConstraints":{"enabled":true,"maxSkew":1,"topologyKey":"topology.kubernetes.io/zone","whenUnsatisfiable":"ScheduleAnyway"},"upstreamMaxRetries":3}` | Sandbox router subchart configuration. The router proxies traffic to sandbox pods and is required for the Python SDK tunnel mode. |
| router.cache | object | `{"enabled":false}` | Pod-IP cache: the router watches sandbox pods and dials the live pod IP instead of resolving DNS per request. |
| router.cache.enabled | bool | `false` | Enable the cache. Creates a router ServiceAccount plus a ClusterRole to get/list/watch pods cluster-wide, and (with the NetworkPolicy) allows egress to the API server. Disabled means DNS-only routing. |
| router.containerPort | int | `8080` | Container port the router proxy listens on inside the pod. |
| router.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000}` | Container-level security context applied to the router container. |
| router.enabled | bool | `true` | Toggle the sandbox router deployment, service, and network policy. |
| router.extraArgs | list | `[]` | Additional router flags (e.g. `--path-routing-prefix`, `--cluster-domain`). |
| router.image | object | `{"digest":"sha256:25b1a09396306eb056ea5b81d6b5ac96ae685e785eb45c84b6416e7d7fac938e","pullPolicy":"IfNotPresent","repository":"registry.k8s.io/agent-sandbox/sandbox-router-go","tag":""}` | Container image used by the router (official Go router). |
| router.image.digest | string | `"sha256:25b1a09396306eb056ea5b81d6b5ac96ae685e785eb45c84b6416e7d7fac938e"` | Pin a specific router image by digest. |
| router.image.pullPolicy | string | `"IfNotPresent"` | This sets the pull policy for the router image. |
| router.image.repository | string | `"registry.k8s.io/agent-sandbox/sandbox-router-go"` | This sets the router image repository. |
| router.image.tag | string | `""` | Overrides the router image tag whose default is the chart appVersion. |
| router.livenessProbe | object | `{"initialDelaySeconds":5,"path":"/healthz","periodSeconds":10}` | HTTP liveness probe configuration for the router (served on the health port 8081). |
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
| router.readinessProbe | object | `{"initialDelaySeconds":1,"path":"/readyz","periodSeconds":5}` | HTTP readiness probe configuration for the router (served on the health port 8081). |
| router.replicaCount | int | `2` | Number of router replicas. |
| router.resources | object | `{"limits":{"cpu":"250m","memory":"512Mi"},"requests":{"cpu":"250m","memory":"512Mi"}}` | Router container resource requests and limits. |
| router.service | object | `{"name":"","port":8080,"type":"ClusterIP"}` | Router `Service` settings. |
| router.service.name | string | `""` | Override the router service name. Defaults to `<release>-agent-sandbox-controller-router-svc`. The Python SDK tunnel mode auto-discovers `sandbox-router-svc` by default, so set this to `sandbox-router-svc` for seamless SDK integration. |
| router.service.port | int | `8080` | Service port exposed by the router. |
| router.service.type | string | `"ClusterIP"` | Service type for the router. |
| router.topologySpreadConstraints | object | `{"enabled":true,"maxSkew":1,"topologyKey":"topology.kubernetes.io/zone","whenUnsatisfiable":"ScheduleAnyway"}` | Spread router replicas across topology domains (defaults to zones). |
| router.upstreamMaxRetries | int | `3` | Retry budget for upstream dial failures. |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532}` | Container-level security context applied to the controller container. |
| service | object | `{"port":8080}` | Controller `Service` settings. |
| service.port | int | `8080` | Service port exposing controller metrics. |
| tolerations | list | `[]` | Tolerations for the controller pod. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
