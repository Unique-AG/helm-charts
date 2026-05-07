# agent-sandbox-controller

Helm chart for the Agent Sandbox controller — a Kubernetes CRD and controller for managing isolated, stateful, singleton workloads (e.g. AI agent runtimes).

Upstream project: https://github.com/kubernetes-sigs/agent-sandbox

![Version: 0.4.5-rc.1](https://img.shields.io/badge/Version-0.4.5--rc.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v0.4.5](https://img.shields.io/badge/AppVersion-v0.4.5-informational?style=flat-square)

## Installation

Releases are published as OCI artifacts to GHCR.

```sh
helm install my-agent-sandbox-controller oci://ghcr.io/unique-ag/helm-charts/agent-sandbox-controller --version 0.4.5-rc.1
```

## Implementation Details

This chart packages the upstream [`kubernetes-sigs/agent-sandbox`](https://github.com/kubernetes-sigs/agent-sandbox) controller. It deploys:

- The controller `Deployment` with leader election enabled by default.
- The `ClusterRole`/`ClusterRoleBinding` and `ServiceAccount` required by the controller.
- An optional extensions controller (`SandboxClaim`, `SandboxTemplate`, `SandboxWarmPool`) toggled via `extensions.enabled`.
- The sandbox `router` deployment, service, and `NetworkPolicy` toggled via `router.enabled`.
- The `Sandbox` and extensions CRDs (installed via Helm's `crds/` mechanism, not templated).

### CRDs

CRDs in `crds/` are installed by Helm on `helm install` but are **not** upgraded or deleted by Helm. To pick up CRD changes on upgrade you must apply them manually:

```sh
kubectl apply -f https://raw.githubusercontent.com/Unique-AG/helm-charts/main/charts/agent-sandbox-controller/crds/crds.yaml
```

### SDK Integration

The Python SDK tunnel mode auto-discovers a service named `sandbox-router-svc`. To opt in, set `router.service.name: sandbox-router-svc` so the router service name matches the SDK default.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for the controller pod. |
| extensions | object | `{"enabled":true}` | Enable the upstream sandbox extensions controller (`SandboxClaim`, `SandboxTemplate`, `SandboxWarmPool`). |
| extensions.enabled | bool | `true` | Toggle the extensions controller and its RBAC. |
| fullnameOverride | string | `""` | This is to override the full name. |
| image | object | `{"digest":"sha256:64317cf5694991d9d63ce6a1b3fda16dfeecca0f01c863945cbcdb38ccc18473","pullPolicy":"IfNotPresent","repository":"registry.k8s.io/agent-sandbox/agent-sandbox-controller","tag":""}` | Container image used by the controller. |
| image.digest | string | `"sha256:64317cf5694991d9d63ce6a1b3fda16dfeecca0f01c863945cbcdb38ccc18473"` | Pin a specific image by digest. Recommended for supply-chain integrity. |
| image.pullPolicy | string | `"IfNotPresent"` | This sets the pull policy for images. |
| image.repository | string | `"registry.k8s.io/agent-sandbox/agent-sandbox-controller"` | This sets the image repository. |
| image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
| leaderElect | bool | `true` | Enable controller leader election (`--leader-elect=true`). |
| nameOverride | string | `""` | This is to override the release name. |
| nodeSelector | object | `{}` | Node selector for the controller pod. |
| podSecurityContext | object | `{"fsGroup":65532,"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context applied to the controller pod. |
| replicaCount | int | `1` | Number of controller replicas. Leader election is used to elect a single active leader. |
| resources | object | `{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}` | Controller container resource requests and limits. |
| router | object | `{"containerPort":8080,"containerSecurityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000},"enabled":true,"image":{"digest":"sha256:2a3a21a5055051109c7ac8230d3d1c83d7f5f50279ae2c669433bb4d16a93e19","pullPolicy":"IfNotPresent","repository":"us-central1-docker.pkg.dev/k8s-staging-images/agent-sandbox/sandbox-router","tag":"v20260506-v0.4.5"},"livenessProbe":{"initialDelaySeconds":10,"path":"/healthz","periodSeconds":10},"networkPolicy":{"egress":{"sandboxNamespaceSelector":{},"sandboxPort":8888},"enabled":true,"ingress":{"allowedCIDRs":[],"allowedSources":[]}},"podSecurityContext":{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"proxyTimeoutSeconds":180,"readinessProbe":{"initialDelaySeconds":5,"path":"/healthz","periodSeconds":5},"replicaCount":2,"resources":{"limits":{"cpu":"250m","memory":"512Mi"},"requests":{"cpu":"250m","memory":"512Mi"}},"service":{"name":"","port":8080,"type":"ClusterIP"},"topologySpreadConstraints":{"enabled":true,"maxSkew":1,"topologyKey":"topology.kubernetes.io/zone","whenUnsatisfiable":"ScheduleAnyway"}}` | Sandbox router subchart configuration. The router proxies traffic to sandbox pods and is required for the Python SDK tunnel mode. |
| router.containerPort | int | `8080` | Container port the router listens on inside the pod. |
| router.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000}` | Container-level security context applied to the router container. |
| router.enabled | bool | `true` | Toggle the sandbox router deployment, service, and network policy. |
| router.image | object | `{"digest":"sha256:2a3a21a5055051109c7ac8230d3d1c83d7f5f50279ae2c669433bb4d16a93e19","pullPolicy":"IfNotPresent","repository":"us-central1-docker.pkg.dev/k8s-staging-images/agent-sandbox/sandbox-router","tag":"v20260506-v0.4.5"}` | Container image used by the router. |
| router.image.digest | string | `"sha256:2a3a21a5055051109c7ac8230d3d1c83d7f5f50279ae2c669433bb4d16a93e19"` | Pin a specific router image by digest. |
| router.image.pullPolicy | string | `"IfNotPresent"` | This sets the pull policy for the router image. |
| router.image.repository | string | `"us-central1-docker.pkg.dev/k8s-staging-images/agent-sandbox/sandbox-router"` | This sets the router image repository. |
| router.image.tag | string | `"v20260506-v0.4.5"` | Overrides the router image tag. |
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

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
