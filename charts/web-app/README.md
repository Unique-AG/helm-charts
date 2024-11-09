# web-app

The 'web-app' chart is a "convenience" chart from Unique AG that can generically be used to deploy web-content serving workloads to Kubernetes.

Note that this chart assumes that you have a valid contract with Unique AG and thus access to the required Docker images.

![Version: 1.4.1](https://img.shields.io/badge/Version-1.4.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

## Implementation Details

### OCI availibility
This chart is available both as Helm Repository as well as OCI artefact.
```sh
helm repo add unique https://unique-ag.github.io/helm-charts/
helm install my-web-app unique/web-app --version 1.4.1

# or
helm install my-web-app oci://ghcr.io/unique-ag/helm-charts/web-app --version 1.4.1
```

### Root Ingress
The Root Ingress is a convenience ingress that routes all traffic from the root of the domain to the backend service. This functionality works different depending on the Ingress Class used. In order to keep the chart agnostic to the Ingress Class, the chart uses the `.Capabilities.APIVersions` [built-in object](https://helm.sh/docs/chart_template_guide/builtin_objects/). If you want to template charts locally you must supply matching capabilities like so:
```
helm template some-app oci://ghcr.io/unique-ag/helm-charts/web-app --api-versions appgw.ingress.azure.io/v1beta1 --values your-own-values.yaml
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| autoscaling.enabled | bool | `false` |  |
| autoscaling.maxReplicas | int | `100` |  |
| autoscaling.minReplicas | int | `1` |  |
| autoscaling.targetCPUUtilizationPercentage | int | `80` |  |
| autoscaling.targetMemoryUtilizationPercentage | int | `80` |  |
| env | object | `{}` |  |
| envSecrets | object | `{}` |  |
| extraEnvCM | list | `[]` |  |
| extraEnvSecrets | list | `[]` |  |
| fullnameOverride | string | `""` |  |
| httproute.additionalRoutes | list | `[]` |  |
| httproute.annotations | object | `{}` |  |
| httproute.enabled | bool | `false` |  |
| httproute.gatewayName | string | `"kong"` |  |
| httproute.gatewayNamespace | string | `"system"` |  |
| httproute.hostnames | list | `[]` |  |
| httproute.rules[0].matches[0].path.type | string | `"PathPrefix"` |  |
| httproute.rules[0].matches[0].path.value | string | `"/"` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `""` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| ingress.enabled | bool | `false` |  |
| ingress.tls.enabled | bool | `false` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| pdb.maxUnavailable | string | `"30%"` |  |
| podAnnotations | object | `{}` |  |
| podSecurityContext | object | `{}` |  |
| probes.enabled | bool | `true` |  |
| probes.liveness.httpGet.path | string | `"/api/health"` |  |
| probes.liveness.httpGet.port | string | `"http"` |  |
| probes.liveness.initialDelaySeconds | int | `5` |  |
| probes.readiness.httpGet.path | string | `"/api/health"` |  |
| probes.readiness.httpGet.port | string | `"http"` |  |
| probes.readiness.initialDelaySeconds | int | `5` |  |
| replicaCount | int | `1` |  |
| resources | object | `{}` |  |
| rollingUpdate.maxSurge | int | `1` |  |
| rollingUpdate.maxUnavailable | int | `0` |  |
| rootIngress | object | `{"debugHeader":false,"enabled":false,"host":"domain.example.com","redirectPath":"/chat"}` | rootIngress is a convenience ingress that routes all traffic from the root of the domain to the backend service. Refer to the readme section "Implementation Details". |
| rootIngress.debugHeader | bool | `false` | Debugging redirection issues can be cumbersome, especially on Azure. You can enable the debugHeader to see the actual path that the request is being redirected to and if it was de facto rerouted. |
| rootIngress.enabled | bool | `false` | Not all web-apps should act as root. In fact, only one deployed chart per cluster should enable this annotation, namely the one that should act as the root. |
| rootIngress.host | string | `"domain.example.com"` | Hostname of the root domain, should match your ingress or httproute settings. |
| rootIngress.redirectPath | string | `"/chat"` | The path to which the root should be redirected to |
| secretProvider | object | `{}` |  |
| securityContext.allowPrivilegeEscalation | bool | `false` |  |
| securityContext.runAsNonRoot | bool | `true` |  |
| securityContext.runAsUser | int | `1000` |  |
| securityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| service.port | int | `3000` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.enabled | bool | `false` |  |
| serviceAccount.name | string | `""` |  |
| strategy.type | string | `"RollingUpdate"` |  |
| tolerations | list | `[]` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
