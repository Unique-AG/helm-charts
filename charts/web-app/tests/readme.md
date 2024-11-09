## `web-app` Unit Tests
Tests are written using [`helm-unittest`](https://github.com/helm-unittest/helm-unittest).

### Install
You need to install `helm-unittest` to run the tests. Refer to the [official docs](https://github.com/helm-unittest/helm-unittest?tab=readme-ov-file#install) for installation instructions.

### Run
```bash
# charts/web-app
helm unittest .
helm unittest . -d # to debug failing tests
```

### `__snapshot__`
If we ever want to use `__snapshot__` we must remove the local `.gitignore`.
