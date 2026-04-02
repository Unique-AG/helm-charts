# agent-sandbox-runtime

![Version: 0.1.0-rc.1](https://img.shields.io/badge/Version-0.1.0--rc.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.0.0](https://img.shields.io/badge/AppVersion-1.0.0-informational?style=flat-square)

Deploys sandbox router, sandbox templates (small/medium/large presets), warm pools, and
network policies for the Agent Sandbox ecosystem. Requires agent-sandbox-controller (CRDs + controller).

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| unique-ag |  | <https://unique.ch/> |

## Source Code

* <https://github.com/Unique-AG/helm-charts/tree/main/charts/agent-sandbox-runtime>
* <https://github.com/kubernetes-sigs/agent-sandbox>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| router.containerPort | int | `8080` |  |
| router.containerSecurityContext.allowPrivilegeEscalation | bool | `false` |  |
| router.containerSecurityContext.capabilities.drop[0] | string | `"ALL"` |  |
| router.containerSecurityContext.readOnlyRootFilesystem | bool | `true` |  |
| router.containerSecurityContext.runAsGroup | int | `1000` |  |
| router.containerSecurityContext.runAsNonRoot | bool | `true` |  |
| router.containerSecurityContext.runAsUser | int | `1000` |  |
| router.enabled | bool | `true` |  |
| router.image.pullPolicy | string | `"IfNotPresent"` |  |
| router.image.repository | string | `"us-central1-docker.pkg.dev/k8s-staging-images/agent-sandbox/sandbox-router"` |  |
| router.image.tag | string | `"v20260402-v0.2.1-53-gc3c9f03"` |  |
| router.livenessProbe.initialDelaySeconds | int | `10` |  |
| router.livenessProbe.path | string | `"/healthz"` |  |
| router.livenessProbe.periodSeconds | int | `10` |  |
| router.podSecurityContext.fsGroup | int | `1000` |  |
| router.podSecurityContext.runAsGroup | int | `1000` |  |
| router.podSecurityContext.runAsNonRoot | bool | `true` |  |
| router.podSecurityContext.runAsUser | int | `1000` |  |
| router.podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| router.proxyTimeoutSeconds | int | `180` |  |
| router.readinessProbe.initialDelaySeconds | int | `5` |  |
| router.readinessProbe.path | string | `"/healthz"` |  |
| router.readinessProbe.periodSeconds | int | `5` |  |
| router.replicaCount | int | `2` |  |
| router.resources.limits.cpu | string | `"1000m"` |  |
| router.resources.limits.memory | string | `"1Gi"` |  |
| router.resources.requests.cpu | string | `"250m"` |  |
| router.resources.requests.memory | string | `"512Mi"` |  |
| router.service.name | string | `""` | Override the router service name. Defaults to "<release>-sandbox-router-svc". The Python SDK tunnel mode auto-discovers "sandbox-router-svc" by default, so set this to "sandbox-router-svc" for seamless SDK integration. |
| router.service.port | int | `8080` |  |
| router.service.type | string | `"ClusterIP"` |  |
| router.topologySpreadConstraints.enabled | bool | `true` |  |
| router.topologySpreadConstraints.maxSkew | int | `1` |  |
| router.topologySpreadConstraints.topologyKey | string | `"topology.kubernetes.io/zone"` |  |
| router.topologySpreadConstraints.whenUnsatisfiable | string | `"ScheduleAnyway"` |  |
| sandboxPresets.large.enabled | bool | `true` |  |
| sandboxPresets.large.resources.limits.cpu | string | `"2000m"` |  |
| sandboxPresets.large.resources.limits.memory | string | `"2Gi"` |  |
| sandboxPresets.large.resources.requests.cpu | string | `"1000m"` |  |
| sandboxPresets.large.resources.requests.memory | string | `"2Gi"` |  |
| sandboxPresets.large.warmPool.enabled | bool | `false` |  |
| sandboxPresets.large.warmPool.replicas | int | `0` |  |
| sandboxPresets.medium.enabled | bool | `true` |  |
| sandboxPresets.medium.resources.limits.cpu | string | `"1000m"` |  |
| sandboxPresets.medium.resources.limits.memory | string | `"1Gi"` |  |
| sandboxPresets.medium.resources.requests.cpu | string | `"500m"` |  |
| sandboxPresets.medium.resources.requests.memory | string | `"1Gi"` |  |
| sandboxPresets.medium.warmPool.enabled | bool | `false` |  |
| sandboxPresets.medium.warmPool.replicas | int | `0` |  |
| sandboxPresets.small.enabled | bool | `true` |  |
| sandboxPresets.small.resources.limits.cpu | string | `"500m"` |  |
| sandboxPresets.small.resources.limits.memory | string | `"512Mi"` |  |
| sandboxPresets.small.resources.requests.cpu | string | `"250m"` |  |
| sandboxPresets.small.resources.requests.memory | string | `"512Mi"` |  |
| sandboxPresets.small.warmPool.enabled | bool | `true` |  |
| sandboxPresets.small.warmPool.replicas | int | `2` |  |
| sandboxTemplate.containerPort | int | `8888` |  |
| sandboxTemplate.containerSecurityContext.allowPrivilegeEscalation | bool | `false` |  |
| sandboxTemplate.containerSecurityContext.capabilities.drop[0] | string | `"ALL"` |  |
| sandboxTemplate.containerSecurityContext.readOnlyRootFilesystem | bool | `true` |  |
| sandboxTemplate.containerSecurityContext.runAsGroup | int | `1000` |  |
| sandboxTemplate.containerSecurityContext.runAsNonRoot | bool | `true` |  |
| sandboxTemplate.containerSecurityContext.runAsUser | int | `1000` |  |
| sandboxTemplate.enabled | bool | `true` |  |
| sandboxTemplate.image.pullPolicy | string | `"IfNotPresent"` |  |
| sandboxTemplate.image.repository | string | `"us-central1-docker.pkg.dev/k8s-staging-images/agent-sandbox/python-runtime-sandbox"` |  |
| sandboxTemplate.image.tag | string | `"v20260402-v0.2.1-53-gc3c9f03"` |  |
| sandboxTemplate.livenessProbe.initialDelaySeconds | int | `2` |  |
| sandboxTemplate.livenessProbe.path | string | `"/"` |  |
| sandboxTemplate.livenessProbe.periodSeconds | int | `10` |  |
| sandboxTemplate.maxCoreSize | int | `0` |  |
| sandboxTemplate.maxOpenFiles | int | `512` |  |
| sandboxTemplate.maxProcesses | int | `0` |  |
| sandboxTemplate.name | string | `"python-sandbox-template"` |  |
| sandboxTemplate.networkPolicy | object | `{"ingress":[{"from":[{"podSelector":{"matchLabels":{"app":"sandbox-router"}}}]}]}` | Custom NetworkPolicy rules applied to sandbox pods via the SandboxTemplate CRD. If omitted (null), the controller creates a secure-by-default deny-all policy. Set explicit ingress/egress rules to allow specific traffic (e.g. from the router). See: https://github.com/kubernetes-sigs/agent-sandbox/blob/main/extensions/examples/secure-sandboxtemplate.yaml |
| sandboxTemplate.networkPolicyManagement | string | `"Managed"` | Network policy management mode: "Managed" (default) or "Unmanaged". When Managed, the controller auto-creates a NetworkPolicy per SandboxTemplate. If no networkPolicy is specified, it defaults to strict isolation (deny all). |
| sandboxTemplate.podSecurityContext.fsGroup | int | `1000` |  |
| sandboxTemplate.podSecurityContext.runAsGroup | int | `1000` |  |
| sandboxTemplate.podSecurityContext.runAsNonRoot | bool | `true` |  |
| sandboxTemplate.podSecurityContext.runAsUser | int | `1000` |  |
| sandboxTemplate.podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| sandboxTemplate.readinessProbe.initialDelaySeconds | int | `0` |  |
| sandboxTemplate.readinessProbe.path | string | `"/"` |  |
| sandboxTemplate.readinessProbe.periodSeconds | int | `1` |  |
| sandboxTemplate.resources.limits.cpu | string | `"1000m"` |  |
| sandboxTemplate.resources.limits.ephemeralStorage | string | `"1Gi"` |  |
| sandboxTemplate.resources.limits.memory | string | `"1Gi"` |  |
| sandboxTemplate.resources.requests.cpu | string | `"250m"` |  |
| sandboxTemplate.resources.requests.ephemeralStorage | string | `"512Mi"` |  |
| sandboxTemplate.resources.requests.memory | string | `"512Mi"` |  |
| sandboxTemplate.restartPolicy | string | `"Never"` |  |
| sandboxTemplate.runtimeClassName | string | `"gvisor"` |  |
| sandboxTemplate.workspacePath | string | `"/workspace"` |  |
| sandboxTemplate.workspaceSizeLimit | string | `"500Mi"` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
