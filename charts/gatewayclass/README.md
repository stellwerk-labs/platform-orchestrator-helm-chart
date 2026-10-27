# gatewayclass

![Version: 0.1.1](https://img.shields.io/badge/Version-0.1.1-informational?style=flat-square)

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| mergeGateways | bool | `false` |  |
| name | string | `"envoy-gateway"` |  |
| service.externalTrafficPolicy | string | `""` | Optional external traffic policy for NodePort or LoadBalancer. Cluster reaches proxy pods on other nodes; Local preserves client IP but requires a proxy pod on the node receiving traffic. Empty keeps Envoy Gateway's default behavior. |
| service.nodePorts.http | int | `30080` |  |
| service.nodePorts.https | int | `30443` |  |
| service.type | string | `"ClusterIP"` |  |
