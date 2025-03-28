# kong-plugins

![Version: 1.0.2](https://img.shields.io/badge/Version-1.0.2-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

The 'kong-plugins' chart provides a streamlined solution for deploying Kong plugins via ConfigMaps to be used with the Unique Software.

Refer to each plugins readme section to learn more about them.

Please report any security concerns with the plugins via the [Security Policy](https://github.com/Unique-AG/helm-charts/tree/main?tab=security-ov-file).

These plugins are forks and adoptions of the https://github.com/telekom-digioss/kong-plugin-jwt-keycloak plugin.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| unique-ag |  | <https://unique.ch/> |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| appRepoAuth | object | `{"appRepositoryUrl":"http://service-app-repository.default.svc:8088","name":"kong-plugin-unique-app-repo-auth"}` | appRepoAuth enables the app-repo-auth plugin |
| appRepoAuth.appRepositoryUrl | string | `"http://service-app-repository.default.svc:8088"` | The default app repository url |
| appRepoAuth.name | string | `"kong-plugin-unique-app-repo-auth"` | The name of the app repository auth config map |
| jwtAuth | object | `{"name":"kong-plugin-unique-jwt-auth"}` | jwtAuth enables the jwt-auth plugin |
| jwtAuth.name | string | `"kong-plugin-unique-jwt-auth"` | The name of the jwt auth config map |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
