# Unique Helm Charts

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/unique)](https://artifacthub.io/packages/search?repo=unique)

Unique `helm-charts` is a collection of charts for [https://unqiue.ch](https://unique.ch) projects.

Most charts are available both as Helm Repository as well as OCI artefact (Unique recommends the latter).
```sh
helm repo add unique https://unique-ag.github.io/helm-charts/
helm install my-<chart> unique/<chart> --version <version>

# or
helm install my-<chart> oci://ghcr.io/unique-ag/helm-charts/<chart> --version <version>
```

You can find comprehensive documentation for each chart in the `charts` directory or on [ArtifactHub#unique](https://artifacthub.io/packages/search?org=unique).

In case the chart you are looking for isn't available over OCI, please open [an issue](https://github.com/Unique-AG/helm-charts/issues/new/choose).

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