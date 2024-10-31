# ai-service

![Version: 1.1.0](https://img.shields.io/badge/Version-1.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

The 'ai-service' chart is a "convenience" chart from Unique AG that can generically be used to deploy simple AI workloads to Kubernetes.

Note that this chart assumes that you have a valid contract with Unique AG and thus access to the required Docker images.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| unique-ag |  | <https://unique.ch/> |

## Source Code

* <https://github.com/Unique-AG/helm-charts/tree/main/charts/ai-service>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| artifactsCache | object | `{"accessModes":["ReadWriteMany"],"artifacts":[],"downloader":{"image":"python:3.9-slim","name":"download-artifacts"},"enabled":false,"storage":"32Gi","storageClassName":"azurefile"}` | Configuration for artifacts cache |
| artifactsCache.accessModes | list | `["ReadWriteMany"]` | Access modes for artifacts cache. Possible values: ReadWriteOnce, ReadOnlyMany, ReadWriteMany |
| artifactsCache.artifacts | list | `[]` | artifactsCache.artifacts[].path Path where to store the downloaded artifact |
| artifactsCache.downloader | object | `{"image":"python:3.9-slim","name":"download-artifacts"}` | Configuration for the artifacts downloader init container |
| artifactsCache.downloader.image | string | `"python:3.9-slim"` | Image to use for the artifacts downloader init container |
| artifactsCache.downloader.name | string | `"download-artifacts"` | Name of the artifacts downloader init container |
| artifactsCache.enabled | bool | `false` | Enable artifacts cache PVC |
| artifactsCache.storage | string | `"32Gi"` | Storage size for artifacts cache |
| artifactsCache.storageClassName | string | `"azurefile"` | Storage class name for artifacts cache |
| autoscaling.enabled | bool | `false` |  |
| autoscaling.maxReplicas | int | `10` |  |
| autoscaling.minReplicas | int | `0` |  |
| autoscaling.targetCPUUtilizationPercentage | int | `80` |  |
| autoscaling.targetMemoryUtilizationPercentage | int | `80` |  |
| deployment | object | `{}` |  |
| env | object | `{}` |  |
| envSecrets | object | `{}` |  |
| eventBasedAutoscaling.cron.desiredReplicas | string | `"1"` |  |
| eventBasedAutoscaling.cron.end | string | `"0 19 * * 1-5"` |  |
| eventBasedAutoscaling.cron.start | string | `"0 8 * * 1-5"` |  |
| eventBasedAutoscaling.cron.timezone | string | `"Europe/Zurich"` |  |
| eventBasedAutoscaling.customTriggers | list | `[]` |  |
| eventBasedAutoscaling.enabled | bool | `true` |  |
| eventBasedAutoscaling.maxReplicaCount | int | `8` |  |
| eventBasedAutoscaling.minReplicaCount | int | `0` |  |
| eventBasedAutoscaling.rabbitmq.hostFromEnv | string | `"AMQP_URL"` |  |
| eventBasedAutoscaling.rabbitmq.mode | string | `"QueueLength"` |  |
| eventBasedAutoscaling.rabbitmq.protocol | string | `"auto"` |  |
| eventBasedAutoscaling.rabbitmq.queueName | string | `""` |  |
| eventBasedAutoscaling.rabbitmq.value | string | `"1"` |  |
| extraEnvCM | list | `[]` |  |
| extraEnvSecrets | list | `[]` |  |
| fullnameOverride | string | `""` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `""` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| ingress.enabled | bool | `false` |  |
| ingress.tls.enabled | bool | `false` |  |
| lifecycle.preStop.httpGet.path | string | `"can_shutdown"` |  |
| lifecycle.preStop.httpGet.port | int | `8081` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| pdb.maxUnavailable | string | `"30%"` |  |
| podAnnotations | object | `{}` |  |
| podSecurityContext | object | `{}` |  |
| probes.enabled | bool | `false` |  |
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
| pvc | object | `{"accessMode":"ReadWriteMany","enabled":false,"storage":"32Gi","storageClassName":"azurefile"}` | Configuration for Persistent Volume Claim |
| pvc.accessMode | string | `"ReadWriteMany"` | Access mode for PVC. Possible values: ReadWriteOnce, ReadOnlyMany, ReadWriteMany |
| pvc.enabled | bool | `false` | Enable persistent volume claim |
| pvc.storage | string | `"32Gi"` | Storage size for PVC |
| pvc.storageClassName | string | `"azurefile"` | Storage class name for PVC |
| replicaCount | int | `1` |  |
| resources | object | `{}` |  |
| rollingUpdate.maxSurge | int | `1` |  |
| rollingUpdate.maxUnavailable | int | `0` |  |
| secretProvider | object | `{}` |  |
| securityContext | object | `{}` |  |
| service.port | int | `8081` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.enabled | bool | `false` |  |
| serviceAccount.workloadIdentity | object | `{}` |  |
| terminationGracePeriodSeconds | int | `3600` |  |
| tolerations | list | `[]` |  |
| volumeMounts | list | `[]` |  |
| volumes | list | `[]` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
