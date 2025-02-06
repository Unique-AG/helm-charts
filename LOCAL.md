# `Makefile` tooling

- `brew install artifacthub/cmd/ah`
- `brew install chart-testing`

# Locally testing charts

You need minikube or a similar tool to test the charts locally. You can use the following command to install a chart locally. You also need [`chart-testing` CLI](https://github.com/helm/chart-testing?tab=readme-ov-file) installed.

```
kubectl config set-context <something_local>
./scripts/install-crds.sh
ct install --config .github/configs/ct-install.yaml
```