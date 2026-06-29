# sscsid-keeper

This chart is deprecated. Unique recommends the External Secrets Operator for managing secrets in Kubernetes.

![Version: 1.5.0](https://img.shields.io/badge/Version-1.5.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

## Implementation Details

### OCI Availability

New releases are published as OCI artifacts only. The Helm repository index is frozen and will not receive new versions—see the [repository README](https://github.com/Unique-AG/helm-charts/blob/main/README.md#migrating-to-oci) for migration steps.

```sh
helm install my-sscsid-keeper oci://ghcr.io/unique-ag/helm-charts/sscsid-keeper --version 1.5.0
```

<details>
<summary>Legacy Helm repository (frozen, no new versions)</summary>

```sh
helm repo add unique https://unique-ag.github.io/helm-charts/
helm install my-sscsid-keeper unique/sscsid-keeper --version 1.5.0
```

</details>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fullnameOverride | string | `""` | This is to override the full name. |
| keeper | object | `{"affinity":{},"image":{"pullPolicy":"IfNotPresent","repository":"busybox","tag":"1.38.0"},"imagePullSecrets":[],"pdb":{"enabled":true,"minAvailable":1},"podAnnotations":{},"podLabels":{},"podSecurityContext":{},"replicaCount":2,"resourcesPreset":"yocto","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true,"runAsUser":1000},"tolerations":[]}` | Set options for the deployed keeper, its deployment and pods respectively. |
| keeper.affinity | object | `{}` | Default affinity preset for the keeper |
| keeper.image | object | `{"pullPolicy":"IfNotPresent","repository":"busybox","tag":"1.38.0"}` | This sets the container image more information can be found here: https://kubernetes.io/docs/concepts/containers/images/ |
| keeper.image.pullPolicy | string | `"IfNotPresent"` | This sets the pull policy for images. |
| keeper.image.repository | string | `"busybox"` | This sets the image repository. |
| keeper.image.tag | string | `"1.38.0"` | Overrides the image tag whose default is the chart appVersion. |
| keeper.imagePullSecrets | list | `[]` | This is for the secretes for pulling an image from a private repository more information can be found here: https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/ |
| keeper.pdb | object | `{"enabled":true,"minAvailable":1}` | Set the PodDisruptionBudget for the keeper |
| keeper.pdb.enabled | bool | `true` | enabled by default as it keeps the secret |
| keeper.pdb.minAvailable | int | `1` | defines how many pods should be kept around, half of the replica in our example |
| keeper.podAnnotations | object | `{}` | This is for setting Kubernetes Annotations to a Pod. For more information checkout: https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/ |
| keeper.podLabels | object | `{}` | This is for setting Kubernetes Labels to a Pod. For more information checkout: https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/ |
| keeper.podSecurityContext | object | `{}` | Toggle and define pod-level security context. |
| keeper.replicaCount | int | `2` | This will set the replicaset count more information can be found here: https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/ |
| keeper.resourcesPreset | string | `"yocto"` | Set container resources according to one common preset (allowed values: none, yocto, zepto, atto). |
| keeper.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true,"runAsUser":1000}` | Toggle and define security context. |
| keeper.tolerations | list | `[]` | Tolerations for the keeper |
| nameOverride | string | `""` | This is to override the release name. |
| spc | object | `{"identityId":"00000000-0000-0000-0000-000000000000","k8sSecretType":"Opaque","kvName":"keyvault-name","labels":{},"secrets":[{"k8sSecretDataKey":"apiKeyExample","kvObjectName":"my-special-example-key"}],"tenantId":"00000000-0000-0000-0000-000000000000"}` | Set options for the Secret Provider Class |
| spc.identityId | string | `"00000000-0000-0000-0000-000000000000"` | Azure Entra ID Identity Client ID |
| spc.k8sSecretType | string | `"Opaque"` | Type of Kubernetes Secret |
| spc.kvName | string | `"keyvault-name"` | Azure KeyVault which stores the secrets, must be available over the network |
| spc.labels | object | `{}` | Set the labels for the Secret Provider Class |
| spc.secrets | list | `[{"k8sSecretDataKey":"apiKeyExample","kvObjectName":"my-special-example-key"}]` | Set the secret objects for the Secret Provider Class |
| spc.secrets[0].k8sSecretDataKey | string | `"apiKeyExample"` | defines, which key in the secret object should be used |
| spc.secrets[0].kvObjectName | string | `"my-special-example-key"` | defines, which object from the Key Vault should be used |
| spc.tenantId | string | `"00000000-0000-0000-0000-000000000000"` | Azure Entra ID Tenant ID wherein the Managed Identity is present |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
