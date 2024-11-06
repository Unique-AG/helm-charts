# backend-service

The 'backend-service' chart is a "convenience" chart from Unique AG that can generically be used to deploy backend workloads to Kubernetes.

Note that this chart assumes that you have a valid contract with Unique AG and thus access to the required Docker images.

![Version: 1.3.4](https://img.shields.io/badge/Version-1.3.4-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

## Implementation Details

### OCI availibility
This chart is available both as Helm Repository as well as OCI artefact.
```sh
helm repo add unique https://unique-ag.github.io/helm-charts/
helm install my-backend-service unique/backend-service --version 1.3.4

# or
helm install my-backend-service oci://ghcr.io/unique-ag/helm-charts/backend-service --version 1.3.4
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| auditVolume.attributes.resourceGroup | string | `"my-azure-resource-group"` |  |
| auditVolume.attributes.storageAccount | string | `"my-azure-storage-account"` |  |
| auditVolume.capacity | string | `"1Ti"` |  |
| auditVolume.enabled | bool | `false` |  |
| auditVolume.mountPath | string | `"/audit"` |  |
| autoscaling.enabled | bool | `false` |  |
| autoscaling.maxReplicas | int | `100` |  |
| autoscaling.minReplicas | int | `1` |  |
| autoscaling.targetCPUUtilizationPercentage | int | `80` |  |
| cronJob.concurrencyPolicy | string | `"Allow"` |  |
| cronJob.enabled | bool | `false` |  |
| cronJob.env | object | `{}` |  |
| cronJob.failedJobsHistoryLimit | int | `1` |  |
| cronJob.jobTemplate.containers.name | string | `""` |  |
| cronJob.jobTemplate.restartPolicy | string | `"OnFailure"` |  |
| cronJob.name | string | `""` |  |
| cronJob.schedule | string | `""` |  |
| cronJob.startingDeadlineSeconds | int | `60` |  |
| cronJob.successfulJobsHistoryLimit | int | `1` |  |
| cronJob.suspend | bool | `false` |  |
| cronJob.timeZone | string | `"Europe/Zurich"` |  |
| deployment.enabled | bool | `true` |  |
| env | object | `{}` |  |
| envSecrets | object | `{}` |  |
| envVars | list | `[]` |  |
| eventBasedAutoscaling.cron.desiredReplicas | string | `"1"` |  |
| eventBasedAutoscaling.cron.end | string | `"0 19 * * 1-5"` |  |
| eventBasedAutoscaling.cron.start | string | `"0 8 * * 1-5"` |  |
| eventBasedAutoscaling.cron.timezone | string | `"Europe/Zurich"` |  |
| eventBasedAutoscaling.customTriggers | list | `[]` |  |
| eventBasedAutoscaling.enabled | bool | `false` |  |
| eventBasedAutoscaling.maxReplicaCount | int | `2` |  |
| eventBasedAutoscaling.minReplicaCount | int | `0` |  |
| eventBasedAutoscaling.rabbitmq.hostFromEnv | string | `"AMQP_URL"` |  |
| eventBasedAutoscaling.rabbitmq.mode | string | `"QueueLength"` |  |
| eventBasedAutoscaling.rabbitmq.protocol | string | `"auto"` |  |
| eventBasedAutoscaling.rabbitmq.value | string | `"1"` |  |
| externalSecrets | list | `[]` |  |
| extraEnvCM | list | `[]` |  |
| extraEnvSecrets | list | `[]` |  |
| extraObjects | list | `[]` | extraObjects allows you to add additional Kubernetes objects to the manifest. It is the responsibility of the user to ensure that the objects are valid, that they do not conflict with the existing objects and that they are not containing any sensitive information |
| fullnameOverride | string | `""` |  |
| hooks.migration.command | string | `""` |  |
| hooks.migration.enabled | bool | `false` |  |
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
| probes.liveness.failureThreshold | int | `6` |  |
| probes.liveness.httpGet.path | string | `"/probe"` |  |
| probes.liveness.httpGet.port | string | `"http"` |  |
| probes.liveness.initialDelaySeconds | int | `10` |  |
| probes.liveness.periodSeconds | int | `5` |  |
| probes.readiness.failureThreshold | int | `6` |  |
| probes.readiness.httpGet.path | string | `"/probe"` |  |
| probes.readiness.httpGet.port | string | `"http"` |  |
| probes.readiness.initialDelaySeconds | int | `10` |  |
| probes.readiness.periodSeconds | int | `5` |  |
| probes.startup.failureThreshold | int | `30` |  |
| probes.startup.httpGet.path | string | `"/probe"` |  |
| probes.startup.httpGet.port | string | `"http"` |  |
| probes.startup.initialDelaySeconds | int | `10` |  |
| probes.startup.periodSeconds | int | `10` |  |
| prometheus.enabled | bool | `false` |  |
| replicaCount | int | `1` |  |
| resources | object | `{}` |  |
| rollingUpdate.maxSurge | int | `1` |  |
| rollingUpdate.maxUnavailable | int | `0` |  |
| secretProvider | object | `{}` |  |
| securityContext | object | `{}` |  |
| service.enabled | bool | `true` |  |
| service.port | int | `80` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.enabled | bool | `false` |  |
| serviceAccount.workloadIdentity | object | `{}` |  |
| tolerations | list | `[]` |  |
| tyk | object | `{"blockList":[{"methods":["GET"],"path":"/metrics"}],"enabled":true,"exposePublicApi":{"enabled":false},"jwtSource":"https://id.unique.app/oauth/v2/keys","listenPath":"/unsert_default_path","rateLimit":{},"scopedApi":{"enabled":false}}` | Settings for Tyk API Gateway respectively its APIDefinition, note that for now, you need the CRDs installed should you enable this |
| tyk.blockList | list | `[{"methods":["GET"],"path":"/metrics"}]` | blockList allows you to block specific paths and methods |
| tyk.listenPath | string | `"/unsert_default_path"` | ⚠️ When using Tyk API Gateway, you must set a valid listenPath |
| volumeMounts | list | `[]` |  |
| volumes | list | `[]` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)