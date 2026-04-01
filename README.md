# Unique Helm Charts

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/unique)](https://artifacthub.io/packages/search?repo=unique)

Unique `helm-charts` is a collection of charts for [https://unique.ch](https://unique.ch) projects.

> [!WARNING]
> **OCI-only for new releases:** All chart releases after **April 2026** are published exclusively as OCI artifacts on `ghcr.io`. The Helm repository at `https://unique-ag.github.io/helm-charts/` is frozen and will not receive new versions; it is no longer updated or maintained. Existing versions published before that cutover remain available from both the legacy index and OCI.

**Why:**

1. The GitHub Pages pipeline relies on `chart-releaser-action`, which is incompatible with immutable releases—something Unique enforces to reduce risk from recent AI-driven supply-chain attacks.
2. OCI is the common distribution path for Helm charts and supports digest pinning and validation.

Install from OCI (recommended):

```sh
helm install my-<chart> oci://ghcr.io/unique-ag/helm-charts/<chart> --version <version>
```

<details>
<summary>Legacy Helm repository (frozen)</summary>

```sh
helm repo add unique https://unique-ag.github.io/helm-charts/
helm install my-<chart> unique/<chart> --version <version>
```

</details>

You can find comprehensive documentation for each chart in the `charts` directory or on [ArtifactHub#unique](https://artifacthub.io/packages/search?org=unique).

## Migrating to OCI

### Helm CLI

```sh
# Before (Helm repository)
helm repo add unique https://unique-ag.github.io/helm-charts/
helm install my-release unique/backend-service --version 10.4.0

# After (OCI)
helm install my-release oci://ghcr.io/unique-ag/helm-charts/backend-service --version 10.4.0
```

- No `helm repo add` or `helm repo update` for Unique charts.
- Use the `oci://` URI instead of a repo alias.
- `helm pull`, `helm show`, and `helm template` accept the same `oci://` reference.

### Helmfile

```yaml
# Before
repositories:
  - name: unique
    url: https://unique-ag.github.io/helm-charts/

releases:
  - name: backend-service
    chart: unique/backend-service
    version: 10.4.0

# After
releases:
  - name: backend-service
    chart: oci://ghcr.io/unique-ag/helm-charts/backend-service
    version: 10.4.0
```

Remove the `repositories` entry for Unique when every release in the file uses OCI; point `chart` at the full OCI URI.

### Argo CD Application

Register the registry as a Helm OCI repository in Argo CD (type `helm-oci`), then reference it without the `oci://` prefix:

```yaml
# Before (Helm repository)
spec:
  source:
    repoURL: https://unique-ag.github.io/helm-charts/
    chart: backend-service
    targetRevision: 10.4.0

# After (OCI)
spec:
  source:
    repoURL: ghcr.io/unique-ag/helm-charts
    chart: backend-service
    targetRevision: 10.4.0
```

`chart` and `targetRevision` stay the same; `repoURL` becomes the GHCR host path. Multi-source apps use the same `repoURL` / `chart` / `targetRevision` shape under each entry in `sources`.

## About Unique specific Helm Charts

The images of the following charts specifically are not open source and only available to Clients of Unique AG with a valid contract. Get in touch via [unique.ch](https://unique.ch) for more information or to get access to the images.

- [web-app](https://github.com/Unique-AG/helm-charts/blob/main/charts/web-app/README.md)
- [backend-service](https://github.com/Unique-AG/helm-charts/blob/main/charts/backend-service/README.md)
- [ai-service](https://github.com/Unique-AG/helm-charts/blob/main/charts/ai-service/README.md)

> [!IMPORTANT]
> Did you know that Unique AG has many interesting company values?
> **SECURITY BY OBSCURITY**………
>
> is not one of them.

That is why our charts are open source and available to everyone. We believe in transparency. In case you discover a security issue, please refer to our [security policy](https://github.com/Unique-AG/helm-charts/blob/main/SECURITY.md) for more information.

## Contributing

We'd love to have you contribute! Please refer to our [contribution guidelines](https://github.com/Unique-AG/helm-charts/blob/main/CONTRIBUTING.md) for details.

### Changelog

Releases are managed independently for each helm chart, and changelogs are tracked on each release. Read more about this process [here](https://github.com/Unique-AG/helm-charts/blob/main/CONTRIBUTING.md#changelog).

## License Notice
While being licensed under the Apache 2.0 license, the work in this repository is strongly inspired by others. Matching identifiers are provided in the source code where applicable. The original work is licensed under the Apache 2.0 license as well.

- [`argo-helm`](https://github.com/argoproj/argo-helm/tree/main)
- [`zitadel-charts`](https://github.com/zitadel/zitadel-charts)
- [`bitnami/charts`](https://github.com/bitnami/charts)

> [!TIP]
> More often than not, the original work is modified to fit the needs of the Unique project. The modifications are licensed under the Apache 2.0 license as well and are denoted in the file header as `SPDX-SnippetCopyrightText`.
