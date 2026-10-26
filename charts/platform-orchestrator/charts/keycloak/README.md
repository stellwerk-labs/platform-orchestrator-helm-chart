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
| image | object | `{"repository":"quay.io/keycloak/keycloak","tag":"26.8.1@sha256:79c623a22abacf3fe6c00a5fb30f5b7843d717b234033b80995891c06116d244"}` | Container image configuration |
| image.repository | string | `"quay.io/keycloak/keycloak"` | Image repository |
| image.tag | string | `"26.8.1@sha256:79c623a22abacf3fe6c00a5fb30f5b7843d717b234033b80995891c06116d244"` | Image tag |
| instances | int | `1` | Number of Keycloak instances |
| resources | object | `{}` | CPU/memory resource requests and limits |
