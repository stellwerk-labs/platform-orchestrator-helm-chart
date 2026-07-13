# gatewayclass

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square)

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| mergeGateways | bool | `false` |  |
| name | string | `"envoy-gateway"` |  |
| service.nodePorts.http | int | `30080` |  |
| service.nodePorts.https | int | `30443` |  |
| service.type | string | `"ClusterIP"` |  |
