# console

A Helm chart for deploying Platform Orchestrator Console

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Pod affinity rules |
| config | object | `{"CONFIG_CAT_SDK_KEY":"","DATADOG_CLIENT_TOKEN":"","ENVIRONMENT_NAME":"production","GOOGLE_CLIENT_ID":"","MICROSOFT_CLIENT_ID":""}` | Environment variables included in the ConfigMap |
| config.CONFIG_CAT_SDK_KEY | string | `""` | ConfigCat SDK key for feature flags (leave empty to disable) |
| config.DATADOG_CLIENT_TOKEN | string | `""` | Datadog client token for RUM monitoring (leave empty to disable) |
| config.ENVIRONMENT_NAME | string | `"production"` | Environment name |
| config.GOOGLE_CLIENT_ID | string | `""` | Google OAuth client ID for social login button (leave empty to hide) |
| config.MICROSOFT_CLIENT_ID | string | `""` | Microsoft OAuth client ID for social login button (leave empty to hide) |
| envFromSecrets | list | `[]` | Names of secrets to load as environment variables via envFrom |
| gatewayApi | object | `{"route":{"matches":[{"path":{"type":"PathPrefix","value":"/"}}]}}` | Gateway API HTTPRoute configuration (created when global Gateway API is enabled) |
| image | object | `{"pullPolicy":"IfNotPresent","repository":"docker.io/library/busybox","tag":"latest"}` | Container image configuration |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| image.repository | string | `"docker.io/library/busybox"` | Image repository |
| image.tag | string | `"latest"` | Image tag |
| nodeSelector | object | `{}` | Node selector constraints |
| podAnnotations | object | `{}` | Additional pod annotations |
| podLabels | object | `{}` | Additional pod labels |
| podSecurityContext | object | `{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context |
| replicaCount | int | `1` | Number of replicas |
| resources | object | `{}` | CPU/memory resource requests and limits |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}` | Container-level security context |
| service | object | `{"port":9000,"type":"ClusterIP"}` | Service configuration |
| service.port | int | `9000` | Service port |
| service.type | string | `"ClusterIP"` | Service type |
| tolerations | list | `[]` | Pod tolerations |
