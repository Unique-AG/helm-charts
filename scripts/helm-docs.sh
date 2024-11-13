#!/bin/bash
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache License 2.0
# SPDX-SnippetCopyrightText: 2024 © Argo Project, argoproj/argo-helm
# SPDX-SnippetCopyrightText: 2024 © Unique AG
# SPDX-SnippetEnd
## Reference: https://github.com/norwoodj/helm-docs
set -eux
HELM_DOCS_VERSION="1.14.2"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "Repo root: $REPO_ROOT"

echo "Running helm-docs"
docker run --rm \
    -v "$REPO_ROOT:/helm-docs" \
    -u $(id -u) \
    jnorwood/helm-docs:v$HELM_DOCS_VERSION