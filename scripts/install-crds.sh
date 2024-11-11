#!/bin/bash
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache License 2.0
# SPDX-SnippetCopyrightText: 2024 © Unique AG
# SPDX-SnippetEnd
set -eux

echo -e "\n-- Installing necessary CRDs --\n"

# csi-secrets-store-provider-azure can not be tested properly for sscsid-keeper as the underlying Machine Identities are not present and thus the pods fail to start
# helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts
# helm install csi csi-secrets-store-provider-azure/csi-secrets-store-provider-azure

kubectl apply -f https://raw.githubusercontent.com/TykTechnologies/tyk-operator/v0.18.0/helm/crds/crds.yaml

# Keda CRD needs --server-side as the CRD is too large (The CustomResourceDefinition "scaledjobs.keda.sh" is invalid: metadata.annotations: Too long: must have at most 262144 bytes)
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.16.0/keda-2.16.0-crds.yaml