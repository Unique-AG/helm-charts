# ai-service

Version 2.2.0 is the last supported iteration of this chart. Subsequent changes will only be supplied to https://artifacthub.io/packages/helm/unique/backend-service. Refer to End of Life Notice in README.md.

> [!IMPORTANT]
> Version `2.2.0` is the last supported iteration of this chart. Subsequent changes will only be supplied to [`unique/backend-service`](https://artifacthub.io/packages/helm/unique/backend-service). Refer to [**End of Life Notice**](#End-of-Life-Notice).

![Version: 2.2.0](https://img.shields.io/badge/Version-2.2.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

## Implementation Details

### OCI availibility
This chart is available both as Helm Repository as well as OCI artefact.
```sh
helm repo add unique https://unique-ag.github.io/helm-charts/
helm install my-ai-service unique/ai-service --version 2.2.0

# or
helm install my-ai-service oci://ghcr.io/unique-ag/helm-charts/ai-service --version 2.2.0
```

### Docker Images
The chart itself uses `ghcr.io/unique-ag/chart-testing-service` as its base image. This is due to automation aspects and because there is no specific `appVersion` or service delivered with it. Using `chart-testing-service` Unique can improve the charts quality without dealing with the complexity of private registries during testing. Naturally, when deploying the Unique product, the image will be replaced with the actual Unique image(s). You can inspect the image [here](https://github.com/Unique-AG/helm-charts/tree/main/docker) and it is served from [`ghcr.io/unique-ag/chart-testing-service`](https://github.com/Unique-AG/helm-charts/pkgs/container/chart-testing-service).

### Artifacts Caching
Packing large language models (LLMs) directly into Docker images is not a scalable or efficient practice for several reasons, including potential security risks:

**Image Size and Deployment**: Including large models in Docker images drastically increases their size, leading to slower build, transfer, and deployment times. This delays updates and consumes unnecessary storage resources across environments.

**Resource Wastage**: Each time the model is updated, the entire image must be rebuilt and redeployed, even if the application code hasn't changed. This is inefficient and unnecessarily resource-intensive.

**Security Risks**
* **Exposure of Sensitive Data**: Embedding models directly in images increases the risk of accidental exposure, especially if the image is pushed to a public or insecure registry. Sensitive proprietary or licensed models may be leaked.
* **Limited Model Access Control**: Using a centralized storage system for model loading allows granular access controls (e.g., authentication, encryption, audit trails). When packed into an image, these controls are harder to enforce.
* **Immutable Images**: * Good practices for container security recommend keeping images immutable and limiting their contents to the application code and necessary dependencies. Packing models violates this principle, making images larger and harder to secure.
**Flexibility and Maintainability**: By externalising models and loading them via a volume or centralized storage, we can independently manage, update, or replace them without impacting the application container. This approach also allows us to apply versioning, secure storage, and controlled access to the models.
**Scalability**: Externalizing models supports shared storage and caching, reducing duplication across containers and enabling efficient scaling without bloating the infrastructure.

For these reasons, we follow industry good practices by loading immutable models from a volume or secure storage. This approach ensures better security, resource efficiency, and operational flexibility.

There is two ways to pre-load/cache models or larger artifacts:

1. [Custom `initContainer`](#custom-initcontainer)
    + It has shown the most self-hosting clients have such a custom setup, that this method is to be preferred, especially when there is no internet access.
1. [Convenience Cache `artifactsCache`](#convenience-cache-artifactscache)

#### Custom `initContainer`
The custom `initContainer` is a bit more tricky to initally bootstrap but allows for the most flexibility.

This example:

1. Bootstraps a custom `initContainer`
2. Creates a PVC to cache the artifacts using an **existing** StorageClass
3. Authenticates with AWS S3 using a secret
4. Uses a customer CA bundle to authenticate with the S3 bucket
5. Downloads the specified files into the PVC or skips if already present

<details>
  <summary><code>values.yaml</code></summary>

  ```yaml
  …
  env:
    …
    MODEL_PATH: "/artifacts/docling-models"
    EASYOCR_MODULE_PATH: "/artifacts/docling-models/"
    AWS_CA_BUNDLE: "/opt/ca-certs.crt"

  envSecrets:
    AWS_ACCESS_KEY_ID: ${filled_by_ci}
    AWS_SECRET_ACCESS_KEY: ${filled_by_ci}
    AWS_DEFAULT_REGION: ${filled_by_ci}
    AWS_ENDPOINT_URL: ${filled_by_ci}

  volumes:
  - name: ca-certs
    secret:
      secretName: ca-trustbundle
  volumeMounts:
  - name: ca-certs
    mountPath: "/opt/ca-certs.crt"
    subPath: ca.crt

  deployment:
    initContainers:
      - name: download-artifacts-custom
        image: amazon/aws-cli:2.24.1
        command:
          - /usr/bin/env
        args:
          - sh
          - -ce
          - |
            echo "Checking and downloading artifact files if needed..."

            cd /artifacts

            download_if_missing() {
              local file=$1
              local url=$2
              if [ ! -f "$file" ]; then
                echo "Downloading $file..."
                for i in 1 2 3; do
                  aws s3 cp "$url" "$file"
                  if [ -f "$file" ]; then
                    echo "$file downloaded successfully"
                    return 0
                  fi
                  echo "Attempt $i failed, retrying..."
                  sleep 5
                done
                echo "Failed to download $file after 3 attempts"
                return 1
              else
                echo "$file already exists, skipping download"
              fi
            }

            download_if_missing "docling-models/config.json" "s3://BUCKET_NAME/models/docling-models/config.json" && \
            download_if_missing "docling-models/model_artifacts/layout/config.json" "s3://BUCKET_NAME/models/docling-models/model_artifacts/layout/config.json" && \
            download_if_missing "docling-models/model_artifacts/layout/preprocessor_config.json" "s3://BUCKET_NAME/models/docling-models/model_artifacts/layout/preprocessor_config.json"
            …
            echo "Download finished"
        volumeMounts:
          - name: artifacts-cache
            mountPath: /artifacts
            readOnly: false
          - name: ca-certs
            mountPath: "/opt/ca-certs.crt"
            subPath: ca.crt
  pvc:
    enabled: true
    name: artifacts-cache
    storage: 30Gi
    storageClassCreationEnabled: false # the SA already exists
    storageClassName: ${filled_by_ci}
  ```
</details>

#### Convenience Cache `artifactsCache`
The artifacts cache provides a mechanism to pre-download and persist files (like ML models) that your service needs. It creates a shared PersistentVolumeClaim that can be accessed by multiple pods, making the files available without needing to download them for each pod.

##### Configuration
Enable the artifacts cache and specify the files to download in your values.yaml:

```yaml
artifactsCache:
  enabled: true
  storage: "32Gi"  # Size of the PVC
  storageClassName: "azurefile"  # Storage class to use
  accessModes:
    - ReadWriteMany  # Allows multiple pods to read the cache
  artifacts: # specify the urls from which the artifacts are to be downloaded and the paths where they are to be saved
    - blobUrl: https://example.com/model1.bin
      path: /models/model1
    - blobUrl: https://example.com/model2.bin
      path: /models/model2
```

##### How it works
When enabled, the chart will:
1. Create a PersistentVolumeClaim for storing the artifacts
    + If you want to use an existing PVC, use the `pvc` section instead and disable the `artifactsCache` option
2. Add an init container that downloads the specified files before your application starts
3. Mount the cache volume at `/artifacts` in your application container

The downloader supports:
- Automatic retries (3 attempts)
- Skip downloading if file already exists
- Custom destination paths within the cache

##### Example Use Cases
Common uses include:
- Pre-downloading ML models
- Caching large data files
- Sharing static assets between pods

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| artifactsCache | object | `{"accessModes":["ReadWriteMany"],"artifacts":[],"downloader":{"image":"curlimages/curl:8.12.0","insecure":false},"enabled":false,"readOnly":true,"storage":"32Gi","storageClassName":"azurefile"}` | Configuration for artifacts cache, see the readme above for examples and details. Only use the cache if you want to actively download artifacts. Else use the `pvc` section. |
| artifactsCache.accessModes | list | `["ReadWriteMany"]` | Access modes for artifacts cache. Possible values: ReadWriteOnce, ReadOnlyMany, ReadWriteMany |
| artifactsCache.artifacts | list | `[]` | artifactsCache.artifacts[].path Path where to store the downloaded artifact |
| artifactsCache.downloader | object | `{"image":"curlimages/curl:8.12.0","insecure":false}` | Configuration for the artifacts downloader init container |
| artifactsCache.downloader.image | string | `"curlimages/curl:8.12.0"` | Image to use for the artifacts downloader init container |
| artifactsCache.enabled | bool | `false` | Enable artifacts cache PVC |
| artifactsCache.readOnly | bool | `true` | By secure default, the artifacts cache is read only, allows writes if needed |
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
| eventBasedAutoscaling.enabled | bool | `false` |  |
| eventBasedAutoscaling.maxReplicaCount | int | `8` |  |
| eventBasedAutoscaling.minReplicaCount | int | `0` |  |
| extraEnvCM | list | `[]` |  |
| extraEnvSecrets | list | `[]` |  |
| fullnameOverride | string | `""` |  |
| image | object | `{"pullPolicy":"IfNotPresent","repository":"ghcr.io/unique-ag/chart-testing-service","tag":"1.0.2"}` | The image to use for this specific deployment and its cron jobs |
| image.pullPolicy | string | `"IfNotPresent"` | pullPolicy, Unique recommends to never use 'Always' |
| image.repository | string | `"ghcr.io/unique-ag/chart-testing-service"` | Repository, where the Unique service image is pulled from - for Unique internal deployments, these is the internal release repository - for client deployments, this will refer to the client's repository where the images have been mirrored too Note that it is bad practice and not advised to directly pull from Uniques release repository Read in the readme on why the helm chart comes bundled with the unique-ag/chart-testing-service image |
| image.tag | string | `"1.0.2"` | tag, most often will refer one of the latest release of the Unique service Read in the readme on why the helm chart comes bundled with the unique-ag/chart-testing-service image |
| imagePullSecrets | list | `[]` |  |
| ingress.enabled | bool | `false` |  |
| ingress.tls.enabled | bool | `false` |  |
| lifecycle.preStop.httpGet.path | string | `"can_shutdown"` |  |
| lifecycle.preStop.httpGet.port | int | `8081` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| pdb.maxUnavailable | string | `"30%"` |  |
| podAnnotations | object | `{}` |  |
| podLabels | object | `{}` | Define additional pod labels for all the pods |
| podSecurityContext | object | `{"seccompProfile":{"type":"RuntimeDefault"}}` | PodSecurityContext for the pod(s) |
| podSecurityContext.seccompProfile | object | `{"type":"RuntimeDefault"}` | seccompProfile, controls the seccomp profile for the container, defaults to 'RuntimeDefault' |
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
| pvc | object | `{"accessMode":"ReadWriteMany","enabled":false,"storage":"32Gi","storageClassCreationEnabled":true,"storageClassName":"azurefile"}` | Configuration for Persistent Volume Claim |
| pvc.accessMode | string | `"ReadWriteMany"` | Access mode for PVC. Possible values: ReadWriteOnce, ReadOnlyMany, ReadWriteMany |
| pvc.enabled | bool | `false` | Enable persistent volume claim |
| pvc.storage | string | `"32Gi"` | Storage size for PVC |
| pvc.storageClassCreationEnabled | bool | `true` | Creating a new storage class for the PVC - defaults to true for backwards compatibility |
| pvc.storageClassName | string | `"azurefile"` | Storage class name for PVC |
| replicaCount | int | `1` |  |
| resources | object | `{}` |  |
| rollingUpdate.maxSurge | int | `1` |  |
| rollingUpdate.maxUnavailable | int | `0` |  |
| secretProvider | object | `{}` |  |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true,"runAsUser":1000}` | securityContext for the container(s) |
| securityContext.allowPrivilegeEscalation | bool | `false` | AllowPrivilegeEscalation, controls if the container can gain more privileges than its parent process, defaults to 'false' |
| securityContext.capabilities | object | `{"drop":["ALL"]}` | capabilities section controls the Linux capabilities for the container |
| securityContext.readOnlyRootFilesystem | bool | `true` | readOnlyRootFilesystem, controls if the container has a read-only root filesystem, defaults to 'true' |
| securityContext.runAsNonRoot | bool | `true` | runAsNonRoot, controls if the container must run as a non-root user, defaults to 'true' |
| securityContext.runAsUser | int | `1000` | runAsUser, controls the user ID that runs the container, defaults to '1000' |
| service.port | int | `8081` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.enabled | bool | `false` |  |
| serviceAccount.workloadIdentity | object | `{}` |  |
| terminationGracePeriodSeconds | int | `3600` |  |
| tolerations | list | `[]` |  |
| volumeMounts | list | `[]` |  |
| volumes | list | `[]` |  |

## End of Life Notice

Unique has historically maintained two distinct Helm charts for backend services: [`unique/backend-service`](https://artifacthub.io/packages/helm/unique/backend-service) and the current `ai-service` chart. While `backend-service` has been actively maintained and regularly updated, the `ai-service` chart has seen limited maintenance due to its lower adoption rate. Analysis shows that `ai-service` provides minimal additional functionality beyond `backend-service`, with its primary distinguishing feature being the `artifactsCache` component, which has seen minimal utilization in production environments.

⚠️ Version `2.2.0` represents the final supported release of this chart.

### Migration Considerations

The primary migration consideration involves the `artifactsCache` functionality. While it is possible to migrate this feature by analyzing the existing implementation, we recommend against a direct 1:1 migration. Instead, we suggest adapting the caching mechanism to your specific infrastructure requirements, as the original implementation was designed for highly customized environments that rarely aligned with typical deployment scenarios.

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
