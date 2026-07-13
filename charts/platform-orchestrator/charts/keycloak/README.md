# keycloak

A Helm chart for creating Keycloak instance for Platform Orchestrator

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| bootstrapAdmin | object | `{"secretName":"keycloak-bootstrap-admin"}` | Bootstrap admin credentials |
| bootstrapAdmin.secretName | string | `"keycloak-bootstrap-admin"` | Secret name containing the initial admin username and password |
| enabled | bool | `true` | Enable Keycloak |
| hostname | object | `{"admin":"","hostname":""}` | Hostname configuration |
| hostname.admin | string | `""` | Admin console hostname (defaults to the public hostname) |
| hostname.hostname | string | `""` | Public hostname for Keycloak (auto-derived from gateway config if empty) |
| image | object | `{"repository":"quay.io/keycloak/keycloak","tag":"26.0.5"}` | Container image configuration |
| image.repository | string | `"quay.io/keycloak/keycloak"` | Image repository |
| image.tag | string | `"26.0.5"` | Image tag |
| instances | int | `1` | Number of Keycloak instances |
| resources | object | `{}` | CPU/memory resource requests and limits |
