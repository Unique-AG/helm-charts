# ai-service

The 'ai-service' chart is a "convenience" chart from Unique AG that can generically be used to deploy simple AI workloads to Kubernetes.

Note that this chart assumes that you have a valid contract with Unique AG and thus access to the required Docker images.

![Version: 1.1.1](https://img.shields.io/badge/Version-1.1.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

## Implementation Details

### OCI availibility
This chart is available both as Helm Repository as well as OCI artefact.
```sh
helm repo add unique https://unique-ag.github.io/helm-charts/
helm install my-ai-service unique/ai-service --version 1.1.1

# or
helm install my-ai-service oci://ghcr.io/unique-ag/helm-charts/ai-service --version 1.1.1
```

### Docker Images
The chart itself uses `busybox` as its base image. This is due to automation aspects and because there is no specific `appVersion` or service delivered with it.  Using `busybox` Unique can improve the charts quality without dealing with the complexity of private registries during testing. Naturally, when deploying the Unique product, the image will be replaced with the actual Unique image(s).

### Artifacts Cache
The artifacts cache provides a mechanism to pre-download and persist files (like ML models) that your service needs. It creates a shared PersistentVolumeClaim that can be accessed by multiple pods, making the files available without needing to download them for each pod.

#### Configuration
Enable the artifacts cache and specify the files to download in your values.yaml:

```yaml
artifactsCache:
  enabled: true
  storage: "32Gi"  # Size of the PVC
  storageClassName: "azurefile"  # Storage class to use
  accessModes:
    - ReadWriteMany  # Allows multiple pods to read the cache
  artifacts: # specify the urls from which the artifacts are to be downloaded and the paths where they are to be saved
    - blobUrl: "https://example.com/model1.bin"
      path: "/models/model1"
    - blobUrl: "https://example.com/model2.bin"
      path: "/models/model2"
```

#### How it works
When enabled, the chart will:
1. Create a PersistentVolumeClaim for storing the artifacts
2. Add an init container that downloads the specified files before your application starts
3. Mount the cache volume at `/artifacts` in your application container

The downloader supports:
- Automatic retries (3 attempts)
- Skip downloading if file already exists
- Custom destination paths within the cache

#### Example Use Cases
Common uses include:
- Pre-downloading ML models
- Caching large data files
- Sharing static assets between pods

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| artifactsCache | object | `{"accessModes":["ReadWriteMany"],"artifacts":[],"downloader":{"image":"python:3.9-slim"},"enabled":false,"storage":"32Gi","storageClassName":"azurefile"}` | Configuration for artifacts cache, see the readme above for examples and details. |
| artifactsCache.accessModes | list | `["ReadWriteMany"]` | Access modes for artifacts cache. Possible values: ReadWriteOnce, ReadOnlyMany, ReadWriteMany |
| artifactsCache.artifacts | list | `[]` | artifactsCache.artifacts[].path Path where to store the downloaded artifact |
| artifactsCache.downloader | object | `{"image":"python:3.9-slim"}` | Configuration for the artifacts downloader init container |
| artifactsCache.downloader.image | string | `"python:3.9-slim"` | Image to use for the artifacts downloader init container |
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
| image | object | `{"pullPolicy":"IfNotPresent","repository":"busybox","tag":"1.37"}` | The image to use for this specific deployment and its cron jobs |
| image.pullPolicy | string | `"IfNotPresent"` | pullPolicy, Unique recommends to never use 'Always' |
| image.repository | string | `"busybox"` | Repository, where the Unique service image is pulled from - for Unique internal deployments, these is the internal release repository - for client deployments, this will refer to the client's repository where the images have been mirrored too Note that it is bad practice and not advised to directly pull from Uniques release repository Read in the readme on why the helm chart comes bundled with the busybox image |
| image.tag | string | `"1.37"` | tag, most often will refer one of the latest release of the Unique service Read in the readme on why the helm chart comes bundled with the busybox image |
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