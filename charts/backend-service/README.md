# backend-service

The 'backend-service' chart is a "convenience" chart from Unique AG that can generically be used to deploy backend workloads to Kubernetes.

Note that this chart assumes that you have a valid contract with Unique AG and thus access to the required Docker images.

![Version: 3.0.2](https://img.shields.io/badge/Version-3.0.2-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

## Implementation Details

### OCI availibility
This chart is available both as Helm Repository as well as OCI artefact.
```sh
helm repo add unique https://unique-ag.github.io/helm-charts/
helm install my-backend-service unique/backend-service --version 3.0.2

# or
helm install my-backend-service oci://ghcr.io/unique-ag/helm-charts/backend-service --version 3.0.2
```

### Docker Images
The chart itself uses `ghcr.io/unique-ag/chart-testing-service` as its base image. This is due to automation aspects and because there is no specific `appVersion` or service delivered with it. Using `chart-testing-service` Unique can improve the charts quality without dealing with the complexity of private registries during testing. Naturally, when deploying the Unique product, the image will be replaced with the actual Unique image(s). You can inspect the image [here](https://github.com/Unique-AG/helm-charts/tree/main/docker) and it is served from [`ghcr.io/unique-ag/chart-testing-service`](https://github.com/Unique-AG/helm-charts/pkgs/container/chart-testing-service).

### Networking
The chart supports two ways of networking in different stages:

- _Tyk_ - Tyk has been source-closed in late 2024 and thus Unique has decided to move away from it. The chart still supports Tyk but it is not enabled by default anymore since `2.0.0`. If you want to use Tyk, you need to set `tyk.enabled: true` in your values file, see [Upgrade ~> 2.0.0](#-200).
    + Support fot Tyk will be removed in the next major release (`3.0.0`).
- _Gateway API_ - The chart supports the Gateway API and its resources. This is the recommended way to go forward. The Gateway API is a Kubernetes-native way to manage your networking resources and is part of the [Gateway API](https://gateway-api.sigs.k8s.io) project.
    + The Gateway API is not enabled by default yet, you need to selectively `enable` different `routes` or use `extraRoutes` to configure them. See [Routes](#routes) for more information.

#### Routes
With `2.0.0` the chart supports _routes_ (namely all routes from [`gateway.networking.k8s.io`](https://gateway-api.sigs.k8s.io/concepts/api-overview/#route-resources)). While `routes`, not yet enabled by default, abstract certain complexity away from the chart consumer, `extraRoutes` can be used by power-users to configure each route exactly to their needs.

To use _Routes_ per se you need two things:

- Knowledge about them and the Gateway API, you can start from these resources:
    + [Gateway API](https://gateway-api.sigs.k8s.io)
    + [Route Resources](https://gateway-api.sigs.k8s.io/concepts/api-overview/#route-resources)
- CRDs installed
    + [Install CRDs](https://gateway-api.sigs.k8s.io/guides/#getting-started-with-gateway-api)

##### HTTPS Redirects
Routes do not redirect to HTTPS by default. This redirect must be handled in the upstream services or extended via `extraAnnotations`. This is not due to a lack of security but the fact that the chart is agnostic to the upstream service and its configuration so enforcing a redirect can lead to unexpected behavior and indefinite redirects. Also, most modern browsers prefix all requests with `https` as a secure practice.

### CronJobs
`cronJob` as well as `extraCronJobs` can be used to create cron jobs. These convenience fields are easing the effort to deploy Unique as package. Technically one can also deploy this same chart multiple times but this increases the management complexity on the user side. `cronJob` and `extraCronJobs` allow to deploy multiple cron jobs in a single chart deployment. Note, that they all share the same environment settings for now and that they base on the same image. You should not use this feature if you want to deploy arbitrary or other CronJobs not related to Unique or the current workload/deployment.

⚠️ The syntax between `cronJob` and `extraCronJobs` is different. This is due to the continuous improvement process of Unique where unnecessary complexity has been abstracted for the user. You might still define every property as before, but the chart will default or auto-generate many of the properties that were mandatory in `cronJob`. Unique leaves is open to deprecate `cronJob` in an upcoming major release and generally advises, to directly use `extraCronJobs` for new deployments.

You can find a `extraCronJobs` example in the [`ci/extra-cronjobs-values.yaml`](https://github.com/Unique-AG/helm-charts/blob/main/charts/backend-service/ci/extra-cronjobs-values.yaml) file.

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
| extraRoutes | object | `{"extra-route-1":{"additionalRules":[],"annotations":{},"apiVersion":"gateway.networking.k8s.io/v1","enabled":false,"filters":[],"hostnames":[],"kind":"HTTPRoute","labels":{},"matches":[{"path":{"type":"PathPrefix","value":"/"}}],"parentRefs":[{"group":"gateway.networking.k8s.io","kind":"Gateway","name":"kong","namespace":"kong-system"}]}}` | BETA: Configure additional gateway routes for the chart here. More routes can be added by adding a dictionary key like the 'extra-route-1' route. In order for this to install, the Gateway [API CRDs](https://gateway-api.sigs.k8s.io/guides/#getting-started-with-gateway-api) must be installed in the cluster. |
| extraRoutes.extra-route-1.annotations | object | `{}` | Set the route annotations |
| extraRoutes.extra-route-1.apiVersion | string | `"gateway.networking.k8s.io/v1"` | Set the route apiVersion, e.g. gateway.networking.k8s.io/v1 or gateway.networking.k8s.io/v1alpha2 |
| extraRoutes.extra-route-1.enabled | bool | `false` | Enables or disables the route |
| extraRoutes.extra-route-1.hostnames | list | `[]` | Add hostnames to the route, will be matched against the host header of the request |
| extraRoutes.extra-route-1.kind | string | `"HTTPRoute"` | Set the route kind Valid options are GRPCRoute, HTTPRoute, TCPRoute, TLSRoute, UDPRoute |
| extraRoutes.extra-route-1.labels | object | `{}` | Set the route labels |
| extraRoutes.extra-route-1.matches | list | `[{"path":{"type":"PathPrefix","value":"/"}}]` | which match conditions should be applied to the route |
| extraRoutes.extra-route-1.parentRefs | list | `[{"group":"gateway.networking.k8s.io","kind":"Gateway","name":"kong","namespace":"kong-system"}]` | parentRefs define the parent gateway(s) that the route will be associated with |
| fullnameOverride | string | `""` |  |
| hooks.migration.command | string | `""` |  |
| hooks.migration.enabled | bool | `false` |  |
| image | object | `{"pullPolicy":"IfNotPresent","repository":"ghcr.io/unique-ag/chart-testing-service","tag":"1.0.3"}` | The image to use for this specific deployment and its cron jobs |
| image.pullPolicy | string | `"IfNotPresent"` | pullPolicy, Unique recommends to never use 'Always' |
| image.repository | string | `"ghcr.io/unique-ag/chart-testing-service"` | Repository, where the Unique service image is pulled from - for Unique internal deployments, these is the internal release repository - for client deployments, this will refer to the client's repository where the images have been mirrored too Note that it is bad practice and not advised to directly pull from Uniques release repository Read in the readme on why the helm chart comes bundled with the unique-ag/chart-testing-service image |
| image.tag | string | `"1.0.3"` | tag, most often will refer one of the latest release of the Unique service Read in the readme on why the helm chart comes bundled with the unique-ag/chart-testing-service image |
| imagePullSecrets | list | `[]` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| pdb.maxUnavailable | string | `"30%"` |  |
| podAnnotations | object | `{}` |  |
| podSecurityContext | object | `{"seccompProfile":{"type":"RuntimeDefault"}}` | PodSecurityContext for the pod(s) |
| podSecurityContext.seccompProfile | object | `{"type":"RuntimeDefault"}` | seccompProfile, controls the seccomp profile for the container, defaults to 'RuntimeDefault' |
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
| routes | object | `{"gateway":{"name":"kong","namespace":"system"},"hostname":"chart-testing-service.example.com","pathPrefix":"","paths":{"default":{"blockList":["/metrics"],"enabled":false,"extraAnnotations":[]},"probe":{"enabled":false,"extraAnnotations":[],"probePath":"/probe"},"scoped":{"allowList":["/upload"],"enabled":false,"extraAnnotations":[],"pathOverride":"/scoped"},"versioned":{"enabled":false,"extraAnnotations":[],"pathOverride":"/public","xApiVersion":"2023-12-06"}}}` | routes is a special object designed for Unique services. It abstracts a lot of complexity and allows for a simple configuration of routes. ⚠️ Unique defaults to Kong as its API Gateway (the middlewares especially), and the routes object is designed to work with Kong (but might work with other implementations as well). If you are using a different API Gateway, you will need to change the `gateway details` or use `extraRoutes`. Refer to [`ci/routes-values.yaml`](https://github.com/Unique-AG/helm-charts/blob/main/charts/backend-service/ci/routes-values.yaml) to see a full example of how to configure routes. Currently, routes must be explicitly enabled until the Unique Kong migration is complete. |
| routes.gateway | object | `{"name":"kong","namespace":"system"}` | gateway to use |
| routes.gateway.name | string | kong | name of the gateway |
| routes.gateway.namespace | string | system | namespace of the gateway |
| routes.pathPrefix | string | defaults to /fullname of the service | pathPrefix allows setting the default prefix (fullname) for all paths |
| routes.paths.default.blockList | list | `["/metrics"]` | explicitly list paths to block |
| routes.paths.probe | object | `{"enabled":false,"extraAnnotations":[],"probePath":"/probe"}` | `/probe` is unauthorized and its sole purpose is to expose a health check endpoint for availability monitoring Maps to version neutral `/probe` endpoint all Unique services expose |
| routes.paths.probe.probePath | string | `"/probe"` | path to the probe endpoint |
| routes.paths.scoped.allowList | list | `["/upload"]` | explicitly list of exact path matches will be rendered to: `/{scoped|pathOverride}/{entry}` |
| routes.paths.scoped.pathOverride | string | the chart will default to 'scoped' to stay backward compatible | users wishing to not call their scoped API 'scoped' can override the path ⚠️ Customizing this value requires also changing the default url in multiple places including all web-apps |
| routes.paths.versioned.pathOverride | string | the chart will default to 'public' to stay backward compatible | users wishing to not call their versioned API 'public' can override the path ⚠️ Customizing this value requires also changing the default url in multiple places including all SDK or integration use cases |
| routes.paths.versioned.xApiVersion | string | the chart will default to "2023-12-06" | specified version of the API to use |
| secretProvider | object | `{}` |  |
| securityContext | object | `{"allowPrivilegeEscalation":false,"readOnlyRootFilesystem":true,"runAsNonRoot":true,"runAsUser":1000}` | SecurityContext for the container(s) |
| securityContext.allowPrivilegeEscalation | bool | `false` | AllowPrivilegeEscalation, controls if the container can gain more privileges than its parent process, defaults to 'false' |
| securityContext.readOnlyRootFilesystem | bool | `true` | readOnlyRootFilesystem, controls if the container has a read-only root filesystem, defaults to 'true' |
| securityContext.runAsNonRoot | bool | `true` | runAsNonRoot, controls if the container must run as a non-root user, defaults to 'true' |
| securityContext.runAsUser | int | `1000` | runAsUser, controls the user ID that runs the container, defaults to '1000' |
| service.enabled | bool | `true` |  |
| service.port | int | `8080` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.enabled | bool | `false` |  |
| serviceAccount.workloadIdentity | object | `{}` |  |
| tolerations | list | `[]` |  |
| tyk | object | `{"blockList":[{"methods":["GET"],"path":"/metrics"}],"enabled":false,"exposePublicApi":{"enabled":false},"jwtSource":"https://id.unique.app/oauth/v2/keys","listenPath":"/unsert_default_path","rateLimit":{},"scopedApi":{"enabled":false}}` | Settings for Tyk API Gateway respectively its APIDefinition, in order to use Tyk API Gateway, you must install its Operators respective CRDs. ⚠️ Since `2.0.0` this is no longer enabled by default. Unique will slowly migrate away from Tyk API Gateway and into `routes` and `extraRoutes`, refer to the readme. ␡ `tyk` will be removed from the chart latest with the next major release (`3.0.0`). |
| tyk.blockList | list | `[{"methods":["GET"],"path":"/metrics"}]` | blockList allows you to block specific paths and methods |
| tyk.listenPath | string | `"/unsert_default_path"` | ⚠️ When using Tyk API Gateway, you must set a valid listenPath |
| volumeMounts | list | `[]` |  |
| volumes | list | `[]` |  |

## Upgrade Guides

### ~> 3.0.0

- `routes` uses `camelCase` for its keys, replace all `lower_snake_case` keys with `camelCase`
- `routes.paths.up` is renamed to `routes.paths.probe`, update your `routes` accordingly

### ~> 2.0.0

- `httproute` is converted into a dictionary and moves into `extraRoutes`
- `ingress` has been removed. Unique Services require an upstream gateway that authenticates requests and populates the headers with matching information from the JWT token.

## Development

If you want to locally template your chart, you must enable this via the `.Capabilities.APIVersions` [built-in object](https://helm.sh/docs/chart_template_guide/builtin_objects/)
```
helm template some-app oci://ghcr.io/unique-ag/helm-charts/backend-service --api-versions gateway.networking.k8s.io/v1 --values your-own-values.yaml
```

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
