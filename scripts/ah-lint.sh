#!/bin/bash
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache License 2.0
# SPDX-SnippetCopyrightText: 2024 © Unique AG
# SPDX-SnippetEnd
# This script runs the ah cli locally. It simulates the linting that is also done by the github action. Run this without any errors before pushing.
# Reference: https://artifacthub.io/docs/topics/cli/#docker
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo -e "\n-- Linting all Helm Charts for Artifact Hub--\n"
ah lint
