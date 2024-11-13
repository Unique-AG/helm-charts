#!/bin/bash
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache License 2.0
# SPDX-SnippetCopyrightText: 2024 © Argo Project, argoproj/argo-helm
# SPDX-SnippetCopyrightText: 2024 © Unique AG
# SPDX-SnippetEnd
# This script runs the chart-testing tool locally. It simulates the linting that is also done by the github action. Run this without any errors before pushing.
# Reference: https://github.com/helm/chart-testing
set -eux

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo -e "\n-- Linting all Helm Charts --\n"
docker run --rm \
     -v "$REPO_ROOT:/workdir" \
     --entrypoint /bin/sh \
     quay.io/helmpack/chart-testing:v3.11.0 \
     -c cd /workdir \
     ct lint \
     --config .github/configs/ct-lint.yaml \
     --lint-conf .github/configs/lintconf.yaml \
     --debug