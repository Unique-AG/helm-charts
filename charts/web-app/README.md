# web-app

The 'web-app' chart is a "convenience" chart from Unique AG that can generically be used to deploy web-content serving workloads to Kubernetes.

Note that this chart assumes that you have a valid contract with Unique AG and thus access to the required Docker images.

![Version: 4.1.1](https://img.shields.io/badge/Version-4.1.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

## Implementation Details

### OCI availibility
This chart is available both as Helm Repository as well as OCI artefact.
```sh
helm repo add unique https://unique-ag.github.io/helm-charts/
helm install my-web-app unique/web-app --version 4.1.1

# or
helm install my-web-app oci://ghcr.io/unique-ag/helm-charts/web-app --version 4.1.1
```

### Docker Images
The chart itself uses `ghcr.io/unique-ag/chart-testing-service` as its base image. This is due to automation aspects and because there is no specific `appVersion` or service delivered with it. Using `chart-testing-service` Unique can improve the charts quality without dealing with the complexity of private registries during testing. Naturally, when deploying the Unique product, the image will be replaced with the actual Unique image(s). You can inspect the image [here](https://github.com/Unique-AG/helm-charts/tree/main/docker) and it is served from [`ghcr.io/unique-ag/chart-testing-service`](https://github.com/Unique-AG/helm-charts/pkgs/container/chart-testing-service).

### Networking
The chart supports the Gateway API and its resources. This is the recommended way to go forward. The Gateway API is a Kubernetes-native way to manage your networking resources and is part of the [Gateway API](https://gateway-api.sigs.k8s.io) project.

The Gateway API is enabled by default, you need to selectively `enable` different `routes` or use `extraRoutes` to configure them. See [Routes](#routes) for more information.

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

##### Root Route
The Root Route is a convenience Ingress/Gateway that routes all traffic from the root of the domain to the applied service. This functionality works different depending on the Ingress/Gateway Class used. In order to keep the chart agnostic to the Ingress Class, the chart uses the `.Capabilities.APIVersions` [built-in object](https://helm.sh/docs/chart_template_guide/builtin_objects/).

Only one root route per cluster (technically per hostname) should be deployed to avoid conflicts or race conditions respectively.

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
| image | object | `{"pullPolicy":"IfNotPresent","repository":"ghcr.io/unique-ag/chart-testing-service","tag":"1.0.2"}` | The image to use for this specific deployment and its cron jobs |
| image.pullPolicy | string | `"IfNotPresent"` | pullPolicy, Unique recommends to never use 'Always' |
| image.repository | string | `"ghcr.io/unique-ag/chart-testing-service"` | Repository, where the Unique service image is pulled from - for Unique internal deployments, these is the internal release repository - for client deployments, this will refer to the client's repository where the images have been mirrored too Note that it is bad practice and not advised to directly pull from Uniques release repository Read in the readme on why the helm chart comes bundled with the unique-ag/chart-testing-service image |
| image.tag | string | `"1.0.2"` | tag, most often will refer one of the latest release of the Unique service Read in the readme on why the helm chart comes bundled with the unique-ag/chart-testing-service image |
| imagePullSecrets | list | `[]` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| pdb | object | `{"minAvailable":1}` | Define the pod disruption budget for this deployment Is templated as YAML so all kuberentes native types are supported |
| pdb.minAvailable | int | `1` | This setting matches the charts default replica count, make sure to adapt your PDB if you chose a different sizing of your deployment |
| podAnnotations | object | `{}` | Define additional pod annotations for all the pods |
| podLabels | object | `{}` | Define additional pod labels for all the pods |
| podSecurityContext | object | `{"seccompProfile":{"type":"RuntimeDefault"}}` | PodSecurityContext for the pod(s) |
| podSecurityContext.seccompProfile | object | `{"type":"RuntimeDefault"}` | seccompProfile, controls the seccomp profile for the container, defaults to 'RuntimeDefault' |
| probes.enabled | bool | `true` |  |
| probes.liveness.httpGet.path | string | `"/api/health"` |  |
| probes.liveness.httpGet.port | string | `"http"` |  |
| probes.liveness.initialDelaySeconds | int | `5` |  |
| probes.readiness.httpGet.path | string | `"/api/health"` |  |
| probes.readiness.httpGet.port | string | `"http"` |  |
| probes.readiness.initialDelaySeconds | int | `5` |  |
| replicaCount | int | `2` | Basic replica count of the deployment make sure to adapt all sizing related values if you change this (e.g. the Pod Disruption Budget `pdb`) |
| resources | object | `{}` |  |
| rollingUpdate.maxSurge | int | `1` |  |
| rollingUpdate.maxUnavailable | int | `0` |  |
| routes | object | `{"gateway":{"name":"kong","namespace":"system"},"hostname":"chart-testing-web-app.example.com","pathPrefix":"","paths":{"default":{"blockList":["/metrics"],"enabled":true,"extraAnnotations":[]},"root":{"enabled":false,"redirectPath":"/chart-testing"}}}` | routes is a special object designed for Unique web-apps. It abstracts a lot of complexity and allows for a simple configuration of routes. ⚠️ Unique defaults to Kong as its API Gateway (the middlewares especially), and the routes object is designed to work with Kong. If you are using a different API Gateway, you will need to use `extraRoutes`. |
| routes.gateway | object | `{"name":"kong","namespace":"system"}` | gateway to use |
| routes.gateway.name | string | kong | name of the gateway |
| routes.gateway.namespace | string | system | namespace of the gateway |
| routes.pathPrefix | string | defaults to the /fullname of the service | pathPrefix allows setting the default prefix (fullname) for all paths |
| routes.paths.default.blockList | list | `["/metrics"]` | explicitly list paths to block |
| routes.paths.root | object | `{"enabled":false,"redirectPath":"/chart-testing"}` | The root route is a convenience route that routes all traffic from the root of the domain to a specific path ⚠️ The root route should only be activated once when multiple web-apps are deployed to the same cluster ⚠️ In order for this to work, the kong-ingress-controller version must be at least `3.4.0` as the `3.3.1` version has a bug that adds a whitespace before the 'location' header (Kong/kubernetes-ingress-controller#6851) |
| routes.paths.root.enabled | bool | `false` | Whether the root route should be enabled |
| routes.paths.root.redirectPath | string | defaults to the `pathPrefix` if enabled and omitted | The path to which the root should be redirected to ⚠️ This value must be a valid full path, not only the sub-path. A 302 redirect will be issued to this path (using full path replacement). |
| secretProvider | object | `{}` |  |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true,"runAsUser":1000}` | securityContext for the container(s) |
| securityContext.allowPrivilegeEscalation | bool | `false` | AllowPrivilegeEscalation, controls if the container can gain more privileges than its parent process, defaults to 'false' |
| securityContext.capabilities | object | `{"drop":["ALL"]}` | capabilities section controls the Linux capabilities for the container |
| securityContext.readOnlyRootFilesystem | bool | `true` | readOnlyRootFilesystem, controls if the container has a read-only root filesystem, defaults to 'true' |
| securityContext.runAsNonRoot | bool | `true` | runAsNonRoot, controls if the container must run as a non-root user, defaults to 'true' |
| securityContext.runAsUser | int | `1000` | runAsUser, controls the user ID that runs the container, defaults to '1000' |
| service.port | int | `3000` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.enabled | bool | `false` |  |
| serviceAccount.name | string | `""` |  |
| strategy.type | string | `"RollingUpdate"` |  |
| tolerations | list | `[]` |  |

## Upgrade Guides

### ~> 3.0.0

- `routes` uses `camelCase` for its keys, replace all `lower_snake_case` keys with `camelCase`
- `routes.paths` and their sub-paths no longer use `/` as a prefix by default, add it to your `routes`

### ~> 2.0.0

- `httproute` is converted into a dictionary and moves into `extraRoutes`
- `ingress` has been removed. If you need `Ingress` back as routing option please open an issue on the repository explaining why.

## Development

If you want to locally template your chart, you must enable this via the `.Capabilities.APIVersions` [built-in object](https://helm.sh/docs/chart_template_guide/builtin_objects/)
```
helm template some-app oci://ghcr.io/unique-ag/helm-charts/web-app --api-versions appgw.ingress.azure.io/v1beta1 --values your-own-values.yaml
helm template some-app oci://ghcr.io/unique-ag/helm-charts/backend-service --api-versions gateway.networking.k8s.io/v1 --values your-own-values.yaml
```

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
