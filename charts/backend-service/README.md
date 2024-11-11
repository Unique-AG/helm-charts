# backend-service

The 'backend-service' chart is a "convenience" chart from Unique AG that can generically be used to deploy backend workloads to Kubernetes.

Note that this chart assumes that you have a valid contract with Unique AG and thus access to the required Docker images.

![Version: 1.4.0](https://img.shields.io/badge/Version-1.4.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

## Implementation Details

### OCI availibility
This chart is available both as Helm Repository as well as OCI artefact.
```sh
helm repo add unique https://unique-ag.github.io/helm-charts/
helm install my-backend-service unique/backend-service --version 1.4.0

# or
helm install my-backend-service oci://ghcr.io/unique-ag/helm-charts/backend-service --version 1.4.0
```

### Docker Images
The chart itself uses `ghcr.io/unique-ag/chart-testing-service` as its base image. This is due to automation aspects and because there is no specific `appVersion` or service delivered with it. Using `chart-testing-service` Unique can improve the charts quality without dealing with the complexity of private registries during testing. Naturally, when deploying the Unique product, the image will be replaced with the actual Unique image(s). You can inspect the image [here](https://github.com/Unique-AG/helm-charts/tree/main/docker) and it is served from [`ghcr.io/unique-ag/chart-testing-service`](https://github.com/Unique-AG/helm-charts/pkgs/container/chart-testing-service).

### CronJobs
`cronJob` as well as `extraCronJobs` can be used to create cron jobs. These convenience fields are easing the effort to deploy Unique as package. Technically one can also deploy this same chart multiple times but this increases the management complexity on the user side. `cronJob` and `extraCronJobs` allow to deploy multiple cron jobs in a single chart deployment. Note, that they all share the same environment settings for now and that they base on the same image. You should not use this feature if you want to deploy arbitrary or other CronJobs not related to Unique or the current workload/deployment.

⚠️ The syntax between `cronJob` and `extraCronJobs` is different. This is due to the continuous improvement process of Unique where unnecessary complexity has been abstracted for the user. You might still define every property as before, but the chart will default or auto-generate many of the properties that were mandatory in `cronJob`. Unique leaves is open to deprecate `cronJob` in an upcoming major release and generally advises, to directly use `extraCronJobs` for new deployments.

You can find a `extraCronJobs` example in the [`example-values/extra-cronjobs.yaml`](https://github.com/Unique-AG/helm-charts/blob/main/charts/backend-service/example-values/extra-cronjobs.yaml) file.

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
| cronJob | object | `{"concurrencyPolicy":"Allow","enabled":false,"env":{},"failedJobsHistoryLimit":1,"jobTemplate":{"containers":{"name":""},"restartPolicy":"OnFailure"},"name":"","schedule":"","startingDeadlineSeconds":60,"successfulJobsHistoryLimit":1,"suspend":false,"timeZone":"Europe/Zurich"}` | cronJob allows you to define a cronJob that mostly bases on the general values. Note that since chart version 1.4.0 it is recommended to use preferably extraCronJobs (see readme for more information) |
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
| extraCronJobs | list | `[]` | extraCronJobs allows you to define additional cron jobs besides 'cronJob' itself. |
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
| image | object | `{"pullPolicy":"IfNotPresent","repository":"ghcr.io/unique-ag/chart-testing-service","tag":"1.0.1"}` | The image to use for this specific deployment and its cron jobs |
| image.pullPolicy | string | `"IfNotPresent"` | pullPolicy, Unique recommends to never use 'Always' |
| image.repository | string | `"ghcr.io/unique-ag/chart-testing-service"` | Repository, where the Unique service image is pulled from - for Unique internal deployments, these is the internal release repository - for client deployments, this will refer to the client's repository where the images have been mirrored too Note that it is bad practice and not advised to directly pull from Uniques release repository Read in the readme on why the helm chart comes bundled with the unique-ag/chart-testing-service image |
| image.tag | string | `"1.0.1"` | tag, most often will refer one of the latest release of the Unique service Read in the readme on why the helm chart comes bundled with the unique-ag/chart-testing-service image |
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
| service.port | int | `8080` |  |
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