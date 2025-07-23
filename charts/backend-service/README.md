# backend-service

The 'backend-service' chart is a "convenience" chart from Unique AG that can generically be used to deploy backend workloads to Kubernetes.

Note that this chart assumes that you have a valid contract with Unique AG and thus access to the required Docker images.

![Version: 4.6.0](https://img.shields.io/badge/Version-4.6.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

## Implementation Details

### OCI availibility
This chart is available both as Helm Repository as well as OCI artefact.
```sh
helm repo add unique https://unique-ag.github.io/helm-charts/
helm install my-backend-service unique/backend-service --version 4.6.0

# or
helm install my-backend-service oci://ghcr.io/unique-ag/helm-charts/backend-service --version 4.6.0
```

### Docker Images
The chart itself uses `ghcr.io/unique-ag/chart-testing-service` as its base image. This is due to automation aspects and because there is no specific `appVersion` or service delivered with it. Using `chart-testing-service` Unique can improve the charts quality without dealing with the complexity of private registries during testing. Naturally, when deploying the Unique product, the image will be replaced with the actual Unique image(s). You can inspect the image [here](https://github.com/Unique-AG/helm-charts/tree/main/docker) and it is served from [`ghcr.io/unique-ag/chart-testing-service`](https://github.com/Unique-AG/helm-charts/pkgs/container/chart-testing-service).

### Networking
The chart supports two ways of networking in different stages:

- _Tyk_ - Tyk has been source-closed in late 2024 and thus Unique has decided to move away from it. The chart still supports Tyk but it is not enabled by default anymore since `2.0.0`. If you want to use Tyk, you need to set `tyk.enabled: true` in your values file, see [Upgrade ~> 2.0.0](#-200).
    + Support fot Tyk will be removed with an upcoming major release.
- _Gateway API_ - The chart supports the Gateway API and its resources. This is the recommended way to go forward. The Gateway API is a Kubernetes-native way to manage your networking resources and is part of the [Gateway API](https://gateway-api.sigs.k8s.io) project.
    + The Gateway API is not enabled by default yet, you need to selectively `enable` different `routes` or use `extraRoutes` to configure them. See [Routes](#routes) for more information.

### Ports
<small>added in `3.1.0`</small>

Unique services communicate with each other extensively. Grown organically from local development, each service used to have its own port. This has grown into kubernetes over time. While technically not a problem, it is a nightmare to set up and manage for Application teams. Since `3.1.0` the chart supports a `ports` object that allows to specify ports for the service and deployment/application.

```yaml
ports:
  application: 8080
  service: 80
```
The port is called `application` because it is the port that the Unique application (that gets deployed using this chart) listens on. The object is nested to allow for future expansion in case another port for a container would be needed. It is not called `containerPort` because there are or can be more than one port for a container and more than one container in a pod.

This change allows Application teams to now use Kubernetes internal networking to communicate with each other way more easily without researching and guessing the correct port.
```yaml
# before
ANOTHER_SERVICE_URL: http://backend-service.namespace.svc:8080

# after
ANOTHER_SERVICE_URL: http://backend-service.namespace.svc
```

The new object `ports` allows also to specify a service port for consistency, but a `service.port` will take precedence over the `ports.service` value.
 to keep non-breaking backward compatibility.

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

### Network Policies
<small>added in `4.4.0`</small>

The chart supports Kubernetes Network Policies to control traffic flow to and from pods. Network Policies are a Kubernetes-native way to implement network segmentation and can help improve security by restricting network communication.

#### Network Policy Flavors
<small>added in `4.4.0`</small>

The chart supports two network policy flavors:

- **`kubernetes`** (default): Standard Kubernetes NetworkPolicy resources
- **`cilium`**: Cilium's CiliumNetworkPolicy resources with enhanced features

```yaml
networkPolicy:
  enabled: true
  flavor: kubernetes  # or "cilium"
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow ingress from monitoring namespace
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
      ports:
        - protocol: TCP
          port: 8080
  egress:
    # Allow egress to database namespace
    - to:
        - namespaceSelector:
            matchLabels:
              name: database
      ports:
        - protocol: TCP
          port: 5432
    # Allow external HTTPS/HTTP access
    - to: []
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 80
```

#### Kubernetes vs Cilium Differences

When using `flavor: cilium`, the chart will:
- Use `apiVersion: cilium.io/v2` and `kind: CiliumNetworkPolicy`
- Use `endpointSelector` instead of `podSelector` in the spec
- Support advanced Cilium-specific features in your rules

When using `flavor: kubernetes` (default), the chart will:
- Use `apiVersion: networking.k8s.io/v1` and `kind: NetworkPolicy`
- Use standard `podSelector` in the spec
- Maintain compatibility with any Kubernetes CNI that supports NetworkPolicy

**Important Notes:**
- Network Policies require a CNI (Container Network Interface) that supports them, such as Calico, Cilium, or Weave Net
- For Cilium flavor, you must have Cilium CNI installed with CiliumNetworkPolicy CRDs
- Once a Network Policy is applied to a pod, it becomes "isolated" and only allowed traffic will be permitted
- Always include DNS resolution (port 53/UDP) in your egress rules if pods need to resolve hostnames
- Test your network policies thoroughly to avoid inadvertently blocking required traffic

You can find Network Policy examples in the [`ci/networkpolicy-values.yaml`](https://github.com/Unique-AG/helm-charts/blob/main/charts/backend-service/ci/networkpolicy-values.yaml) (Kubernetes) and [`ci/networkpolicy-cilium-values.yaml`](https://github.com/Unique-AG/helm-charts/blob/main/charts/backend-service/ci/networkpolicy-cilium-values.yaml) (Cilium) files.

### CronJobs
`cronJob` as well as `extraCronJobs` can be used to create cron jobs. These convenience fields are easing the effort to deploy Unique as package. Technically one can also deploy this same chart multiple times but this increases the management complexity on the user side. `cronJob` and `extraCronJobs` allow to deploy multiple cron jobs in a single chart deployment. Note, that they all share the same environment settings for now and that they base on the same image. You should not use this feature if you want to deploy arbitrary or other CronJobs not related to Unique or the current workload/deployment.

⚠️ The syntax between `cronJob` and `extraCronJobs` is different. This is due to the continuous improvement process of Unique where unnecessary complexity has been abstracted for the user. You might still define every property as before, but the chart will default or auto-generate many of the properties that were mandatory in `cronJob`. Unique leaves is open to deprecate `cronJob` in an upcoming major release and generally advises, to directly use `extraCronJobs` for new deployments.

You can find a `extraCronJobs` example in the [`ci/extra-cronjobs-values.yaml`](https://github.com/Unique-AG/helm-charts/blob/main/charts/backend-service/ci/extra-cronjobs-values.yaml) file.

## JSON Schema

The chart provides a JSON schema for validating `values.yaml` files. This schema helps with:
- Validating values against the expected structure
- Providing IDE hints and autocompletion when editing values.yaml files
- Documenting the accepted values and their types

The schema is available in the `values.schema.json` file in the chart.

## Upgrade Guides

### ~> `3.0.0`

- `routes` uses `camelCase` for its keys, replace all `lower_snake_case` keys with `camelCase`
- `routes.paths.up` is renamed to `routes.paths.probe`, update your `routes` accordingly

### ~> `2.0.0`

- `httproute` is converted into a dictionary and moves into `extraRoutes`
- `ingress` has been removed. Unique Services require an upstream gateway that authenticates requests and populates the headers with matching information from the JWT token.

## Development

If you want to locally template your chart, you must enable this via the `.Capabilities.APIVersions` [built-in object](https://helm.sh/docs/chart_template_guide/builtin_objects/)
```
helm template some-app oci://ghcr.io/unique-ag/helm-charts/backend-service --api-versions gateway.networking.k8s.io/v1 --values your-own-values.yaml
```

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
