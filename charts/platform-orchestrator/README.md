# platform-orchestrator

Platform Orchestrator

## Architecture

The chart deploys the following components:

| Component | Subchart | Description |
|-----------|----------|-------------|
| **Control Plane** | `backend-module` (alias) | Manages orgs, projects, environments, modules, and runners |
| **Data Plane** | `backend-module` (alias) | Handles deployments, active resources, and logs |
| **IAM** | `backend-module` (alias) | Authentication, authorization, SSO, and user management |
| **Console** | `console` | Web-based UI |
| **PostgreSQL** | `cnpg-databases` | CloudNativePG-managed PostgreSQL cluster |
| **RabbitMQ** | `rabbitmq` | AMQP message broker |
| **SeaweedFS** | `seaweed` | S3-compatible object storage for runner logs |
| **SpiceDB** | `spicedb` | Zanzibar-inspired authorization engine |
| **Keycloak** | `keycloak` | Identity provider and SSO |

## Prerequisites

- Kubernetes 1.27+
- Helm 3.x
- [cert-manager](https://cert-manager.io/) (for TLS certificates)
- [Gateway API CRDs](https://gateway-api.sigs.k8s.io/) and a gateway controller (e.g., Envoy Gateway)
- [CloudNativePG Operator](https://cloudnative-pg.io/) (if using the in-cluster PostgreSQL)
- [RabbitMQ Cluster Operator](https://www.rabbitmq.com/kubernetes/operator/operator-overview) (if using the in-cluster RabbitMQ)
- OpenBao (external dependency, Vault-compatible)

## Installation

```bash
helm install platform-orchestrator ./charts/platform-orchestrator \
  --namespace platform-orchestrator \
  --create-namespace \
  -f my-values.yaml
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cnpg-databases | object | `{"enabled":true}` | CNPG PostgreSQL databases subchart |
| cnpg-databases.enabled | bool | `true` | Enable the in-cluster PostgreSQL database (disable to use external DB) |
| console | object | `{"config":{"CONFIG_CAT_SDK_KEY":"","DATADOG_CLIENT_TOKEN":"","DEPLOYMENT_MODE":"self-hosted","GOOGLE_CLIENT_ID":"","MICROSOFT_CLIENT_ID":""},"image":{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-frontend","tag":"v1.0.1"}}` | --------------------------------------------------------------------------- The web-based UI for the Platform Orchestrator. |
| console.config | object | `{"CONFIG_CAT_SDK_KEY":"","DATADOG_CLIENT_TOKEN":"","DEPLOYMENT_MODE":"self-hosted","GOOGLE_CLIENT_ID":"","MICROSOFT_CLIENT_ID":""}` | Configuration environment variables (injected via ConfigMap) |
| console.config.CONFIG_CAT_SDK_KEY | string | `""` | ConfigCat SDK key for feature flags (leave empty to disable) |
| console.config.DATADOG_CLIENT_TOKEN | string | `""` | Datadog client token for RUM monitoring (leave empty to disable) |
| console.config.DEPLOYMENT_MODE | string | `"self-hosted"` | Deployment mode identifier |
| console.config.GOOGLE_CLIENT_ID | string | `""` | Google OAuth client ID for social login button (leave empty to hide) |
| console.config.MICROSOFT_CLIENT_ID | string | `""` | Microsoft OAuth client ID for social login button (leave empty to hide) |
| console.image | object | `{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-frontend","tag":"v1.0.1"}` | Container image for the console |
| console.image.repository | string | `"ghcr.io/stellwerk-labs/platform-orchestrator-frontend"` | Image repository. Prepend repository hostname and path as per your setup, e.g. `my-registry.example.com/orchestrator/platform-orchestrator-frontend` |
| console.image.tag | string | `"v1.0.1"` | Image tag |
| control-plane | object | `{"config":{"DATABASE_HOST":"platform-orchestrator-cnpg-databases","DATABASE_NAME":"orchestrator-controlplane","DATABASE_PORT":"5432","OTEL_EXPORTER_OTLP_ENDPOINT":"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317","VAULT_AUTH":"kubernetes:platform-orchestrator-control-plane:platform-orchestrator","VAULT_ROLE":"orchestrator-control-plane"},"env":[{"name":"DATABASE_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"controlplane-db-secret"}}},{"name":"DATABASE_USER","valueFrom":{"secretKeyRef":{"key":"username","name":"controlplane-db-secret"}}},{"name":"AMQP_USERNAME","valueFrom":{"secretKeyRef":{"key":"username","name":"platform-orchestrator-rabbitmq-platform-user-credentials"}}},{"name":"AMQP_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"platform-orchestrator-rabbitmq-platform-user-credentials"}}}],"gatewayApi":{"route":{"admin":{"matches":[{"path":{"type":"PathPrefix","value":"/admin/orgs"}}],"rewrite":{"path":{"replacePrefixMatch":"/internal/orgs","type":"ReplacePrefixMatch"}}},"matches":[{"path":{"type":"RegularExpression","value":"/orgs($|/[^/]+/(projects|env-types|resource-types|module-providers|runners|runner-rules|modules|module-rules)($|/.*))"}}]}},"image":{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-cp","tag":"v1.0.1"},"serviceAccount":{"allowCreateToken":true}}` | --------------------------------------------------------------------------- The control plane manages organizations, projects, environments, modules, and runners. It is deployed as a backend-module subchart. |
| control-plane.config | object | `{"DATABASE_HOST":"platform-orchestrator-cnpg-databases","DATABASE_NAME":"orchestrator-controlplane","DATABASE_PORT":"5432","OTEL_EXPORTER_OTLP_ENDPOINT":"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317","VAULT_AUTH":"kubernetes:platform-orchestrator-control-plane:platform-orchestrator","VAULT_ROLE":"orchestrator-control-plane"}` | Configuration environment variables (injected via ConfigMap) |
| control-plane.config.DATABASE_HOST | string | `"platform-orchestrator-cnpg-databases"` | PostgreSQL host (should match the CNPG cluster service name) |
| control-plane.config.DATABASE_NAME | string | `"orchestrator-controlplane"` | PostgreSQL database name for the control plane |
| control-plane.config.DATABASE_PORT | string | `"5432"` | PostgreSQL port |
| control-plane.config.OTEL_EXPORTER_OTLP_ENDPOINT | string | `"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317"` | OpenTelemetry collector endpoint |
| control-plane.config.VAULT_AUTH | string | `"kubernetes:platform-orchestrator-control-plane:platform-orchestrator"` | Vault authentication string Format: "kubernetes:<service account name>:<audience1>,<audience2>" |
| control-plane.config.VAULT_ROLE | string | `"orchestrator-control-plane"` | Vault role for the control plane |
| control-plane.env | list | `[{"name":"DATABASE_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"controlplane-db-secret"}}},{"name":"DATABASE_USER","valueFrom":{"secretKeyRef":{"key":"username","name":"controlplane-db-secret"}}},{"name":"AMQP_USERNAME","valueFrom":{"secretKeyRef":{"key":"username","name":"platform-orchestrator-rabbitmq-platform-user-credentials"}}},{"name":"AMQP_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"platform-orchestrator-rabbitmq-platform-user-credentials"}}}]` | Additional environment variables (injected directly into the pod spec) Typically used for secret references |
| control-plane.gatewayApi | object | `{"route":{"admin":{"matches":[{"path":{"type":"PathPrefix","value":"/admin/orgs"}}],"rewrite":{"path":{"replacePrefixMatch":"/internal/orgs","type":"ReplacePrefixMatch"}}},"matches":[{"path":{"type":"RegularExpression","value":"/orgs($|/[^/]+/(projects|env-types|resource-types|module-providers|runners|runner-rules|modules|module-rules)($|/.*))"}}]}}` | Gateway API HTTPRoute configuration for the control plane |
| control-plane.gatewayApi.route.admin | object | `{"matches":[{"path":{"type":"PathPrefix","value":"/admin/orgs"}}],"rewrite":{"path":{"replacePrefixMatch":"/internal/orgs","type":"ReplacePrefixMatch"}}}` | Admin API route configuration (rewrites /admin/orgs -> /internal/orgs) |
| control-plane.gatewayApi.route.matches | list | `[{"path":{"type":"RegularExpression","value":"/orgs($|/[^/]+/(projects|env-types|resource-types|module-providers|runners|runner-rules|modules|module-rules)($|/.*))"}}]` | Path matching rules for control plane API endpoints |
| control-plane.image | object | `{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-cp","tag":"v1.0.1"}` | Container image for the control plane |
| control-plane.image.repository | string | `"ghcr.io/stellwerk-labs/platform-orchestrator-cp"` | Image repository. Prepend repository hostname and path as per your setup, e.g. `my-registry.example.com/orchestrator/platform-orchestrator-cp` |
| control-plane.image.tag | string | `"v1.0.1"` | Image tag |
| control-plane.serviceAccount | object | `{"allowCreateToken":true}` | Service account configuration |
| control-plane.serviceAccount.allowCreateToken | bool | `true` | Allow the service account to create tokens (needed for Vault auth) |
| data-plane | object | `{"config":{"DATABASE_HOST":"platform-orchestrator-cnpg-databases","DATABASE_NAME":"orchestrator-dataplane","DATABASE_PORT":"5432","INTERNAL_DATAPLANE_HOSTNAME":"platform-orchestrator-data-plane.platform-orchestrator.svc.cluster.local","K8S_RUNNER_POD_SCHEDULING_DELAY":"30s","OIDC_ISSUER_URL":"","OTEL_EXPORTER_OTLP_ENDPOINT":"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317","RUNNER_IMAGE":"ghcr.io/stellwerk-labs/platform-orchestrator-runner:v1.0.0","RUNNER_LOGS_BUCKET":"deployment-runner-logs","RUNNER_LOGS_BUCKET_ENDPOINT":"http://platform-orchestrator-seaweed-filer.platform-orchestrator.svc.cluster.local:8333","VAULT_AUTH":"kubernetes:platform-orchestrator-data-plane:platform-orchestrator","VAULT_ROLE":"orchestrator-data-plane"},"env":[{"name":"DATABASE_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"dataplane-db-secret"}}},{"name":"DATABASE_USER","valueFrom":{"secretKeyRef":{"key":"username","name":"dataplane-db-secret"}}},{"name":"AMQP_USERNAME","valueFrom":{"secretKeyRef":{"key":"username","name":"platform-orchestrator-rabbitmq-platform-user-credentials"}}},{"name":"AMQP_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"platform-orchestrator-rabbitmq-platform-user-credentials"}}},{"name":"RUNNER_TOKEN_SALT","valueFrom":{"secretKeyRef":{"key":"runnerTokenSalt","name":"platform-orchestrator-secrets"}}},{"name":"RUNNER_LOGS_BUCKET_CREDS","valueFrom":{"secretKeyRef":{"key":"credentials_json","name":"platform-orchestrator-s3-admin-credentials"}}}],"gatewayApi":{"route":{"matches":[{"path":{"type":"RegularExpression","value":"/orgs/[^/]+/(deployments|last-deployments|active-resources|metadata-keys|remote-runners)($|/.*)"}}],"timeouts":{"request":"45s"}}},"gatewayApiOidc":{"route":{"matches":[{"path":{"type":"RegularExpression","value":"/(.well-known/openid-configuration|.well-known/jwks)"}}]}},"image":{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-dp","tag":"v1.0.1"},"service":{"createHeadless":true},"serviceAccount":{"allowCreateToken":true}}` | --------------------------------------------------------------------------- The data plane handles deployments, active resources and logs. It is deployed as a backend-module subchart. |
| data-plane.config | object | `{"DATABASE_HOST":"platform-orchestrator-cnpg-databases","DATABASE_NAME":"orchestrator-dataplane","DATABASE_PORT":"5432","INTERNAL_DATAPLANE_HOSTNAME":"platform-orchestrator-data-plane.platform-orchestrator.svc.cluster.local","K8S_RUNNER_POD_SCHEDULING_DELAY":"30s","OIDC_ISSUER_URL":"","OTEL_EXPORTER_OTLP_ENDPOINT":"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317","RUNNER_IMAGE":"ghcr.io/stellwerk-labs/platform-orchestrator-runner:v1.0.0","RUNNER_LOGS_BUCKET":"deployment-runner-logs","RUNNER_LOGS_BUCKET_ENDPOINT":"http://platform-orchestrator-seaweed-filer.platform-orchestrator.svc.cluster.local:8333","VAULT_AUTH":"kubernetes:platform-orchestrator-data-plane:platform-orchestrator","VAULT_ROLE":"orchestrator-data-plane"}` | Configuration environment variables (injected via ConfigMap) |
| data-plane.config.DATABASE_HOST | string | `"platform-orchestrator-cnpg-databases"` | PostgreSQL host (should match the CNPG cluster service name) |
| data-plane.config.DATABASE_NAME | string | `"orchestrator-dataplane"` | PostgreSQL database name for the data plane |
| data-plane.config.DATABASE_PORT | string | `"5432"` | PostgreSQL port |
| data-plane.config.INTERNAL_DATAPLANE_HOSTNAME | string | `"platform-orchestrator-data-plane.platform-orchestrator.svc.cluster.local"` | Internal data plane hostname (headless service FQDN) Format: <headless svc name>.<namespace>.svc.cluster.local |
| data-plane.config.K8S_RUNNER_POD_SCHEDULING_DELAY | string | `"30s"` | Scheduling delay for runner pods |
| data-plane.config.OIDC_ISSUER_URL | string | `""` | OIDC issuer URL for the built-in OIDC provider (leave empty to disable) |
| data-plane.config.OTEL_EXPORTER_OTLP_ENDPOINT | string | `"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317"` | OpenTelemetry collector endpoint |
| data-plane.config.RUNNER_IMAGE | string | `"ghcr.io/stellwerk-labs/platform-orchestrator-runner:v1.0.0"` | Runner image used for deployments. Prepend repository hostname and path as per your setup, e.g. `my-registry.example.com/orchestrator/platform-orchestrator-runner:vX.Y.Z` |
| data-plane.config.RUNNER_LOGS_BUCKET | string | `"deployment-runner-logs"` | S3 bucket name for runner deployment logs |
| data-plane.config.RUNNER_LOGS_BUCKET_ENDPOINT | string | `"http://platform-orchestrator-seaweed-filer.platform-orchestrator.svc.cluster.local:8333"` | S3-compatible endpoint for runner logs (SeaweedFS filer) |
| data-plane.config.VAULT_AUTH | string | `"kubernetes:platform-orchestrator-data-plane:platform-orchestrator"` | Vault authentication string Format: "kubernetes:<service account name>:<audience1>,<audience2>" |
| data-plane.config.VAULT_ROLE | string | `"orchestrator-data-plane"` | Vault role for the data plane |
| data-plane.env | list | `[{"name":"DATABASE_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"dataplane-db-secret"}}},{"name":"DATABASE_USER","valueFrom":{"secretKeyRef":{"key":"username","name":"dataplane-db-secret"}}},{"name":"AMQP_USERNAME","valueFrom":{"secretKeyRef":{"key":"username","name":"platform-orchestrator-rabbitmq-platform-user-credentials"}}},{"name":"AMQP_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"platform-orchestrator-rabbitmq-platform-user-credentials"}}},{"name":"RUNNER_TOKEN_SALT","valueFrom":{"secretKeyRef":{"key":"runnerTokenSalt","name":"platform-orchestrator-secrets"}}},{"name":"RUNNER_LOGS_BUCKET_CREDS","valueFrom":{"secretKeyRef":{"key":"credentials_json","name":"platform-orchestrator-s3-admin-credentials"}}}]` | Additional environment variables (injected directly into the pod spec) Typically used for secret references |
| data-plane.gatewayApi | object | `{"route":{"matches":[{"path":{"type":"RegularExpression","value":"/orgs/[^/]+/(deployments|last-deployments|active-resources|metadata-keys|remote-runners)($|/.*)"}}],"timeouts":{"request":"45s"}}}` | Gateway API HTTPRoute configuration for the data plane |
| data-plane.gatewayApi.route.matches | list | `[{"path":{"type":"RegularExpression","value":"/orgs/[^/]+/(deployments|last-deployments|active-resources|metadata-keys|remote-runners)($|/.*)"}}]` | Path matching rules for data plane API endpoints |
| data-plane.gatewayApi.route.timeouts | object | `{"request":"45s"}` | Request timeout for data plane routes |
| data-plane.gatewayApiOidc | object | `{"route":{"matches":[{"path":{"type":"RegularExpression","value":"/(.well-known/openid-configuration|.well-known/jwks)"}}]}}` | Gateway API HTTPRoute for OIDC endpoints (built-in OIDC provider) |
| data-plane.image | object | `{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-dp","tag":"v1.0.1"}` | Container image for the data plane |
| data-plane.image.repository | string | `"ghcr.io/stellwerk-labs/platform-orchestrator-dp"` | Image repository. Prepend repository hostname and path as per your setup, e.g. `my-registry.example.com/orchestrator/platform-orchestrator-dp` |
| data-plane.image.tag | string | `"v1.0.1"` | Image tag |
| data-plane.service | object | `{"createHeadless":true}` | Service configuration |
| data-plane.service.createHeadless | bool | `true` | Create a headless service (required for internal data plane communication) |
| data-plane.serviceAccount | object | `{"allowCreateToken":true}` | Service account configuration |
| data-plane.serviceAccount.allowCreateToken | bool | `true` | Allow the service account to create tokens (needed for Vault auth) |
| global.certificates | object | `{"createIssuer":true,"enabled":true,"issuer":{"acme":{"email":"","privateKeySecretRef":"letsencrypt-account-key","server":"https://acme-v02.api.letsencrypt.org/directory","solvers":[]},"ca":{"secretName":"ca-key-pair"},"type":"selfSigned"},"issuerRef":{"kind":"ClusterIssuer","name":"platform-orchestrator-issuer"}}` | ------------------------------------------------------------------------- |
| global.certificates.createIssuer | bool | `true` | Create a ClusterIssuer resource (set to false if one already exists) |
| global.certificates.enabled | bool | `true` | Enable automatic TLS certificate generation via cert-manager |
| global.certificates.issuer | object | `{"acme":{"email":"","privateKeySecretRef":"letsencrypt-account-key","server":"https://acme-v02.api.letsencrypt.org/directory","solvers":[]},"ca":{"secretName":"ca-key-pair"},"type":"selfSigned"}` | Issuer configuration (only used when createIssuer is true) |
| global.certificates.issuer.acme | object | `{"email":"","privateKeySecretRef":"letsencrypt-account-key","server":"https://acme-v02.api.letsencrypt.org/directory","solvers":[]}` | ACME issuer configuration (used when type is "acme") |
| global.certificates.issuer.acme.email | string | `""` | Email address for ACME registration |
| global.certificates.issuer.acme.privateKeySecretRef | string | `"letsencrypt-account-key"` | Name of the secret to store the ACME account private key |
| global.certificates.issuer.acme.server | string | `"https://acme-v02.api.letsencrypt.org/directory"` | ACME server URL |
| global.certificates.issuer.acme.solvers | list | `[]` | ACME challenge solvers configuration Example HTTP-01 solver:   - http01:       ingress:         class: envoy-gateway |
| global.certificates.issuer.ca | object | `{"secretName":"ca-key-pair"}` | CA issuer configuration (used when type is "ca") Requires a pre-existing secret with tls.crt and tls.key |
| global.certificates.issuer.ca.secretName | string | `"ca-key-pair"` | Name of the secret containing the CA certificate key pair |
| global.certificates.issuer.type | string | `"selfSigned"` | Issuer type: "selfSigned", "ca", or "acme" |
| global.certificates.issuerRef | object | `{"kind":"ClusterIssuer","name":"platform-orchestrator-issuer"}` | Reference to the cert-manager issuer to use for certificates |
| global.config | object | `{"AMQP_HOST":"platform-orchestrator-rabbitmq","AMQP_PORT":"5672","AMQP_VHOST":"platform","CONTROL_PLANE_URL":"http://platform-orchestrator-control-plane:8080","DATA_PLANE_URL":"http://platform-orchestrator-data-plane:8080","IAM_URL":"http://platform-orchestrator-iam:8080","VAULT_URL":"http://openbao.openbao:8200"}` | ------------------------------------------------------------------------- These are used for inter-service communication within the cluster. |
| global.config.AMQP_HOST | string | `"platform-orchestrator-rabbitmq"` | RabbitMQ host |
| global.config.AMQP_PORT | string | `"5672"` | RabbitMQ port |
| global.config.AMQP_VHOST | string | `"platform"` | RabbitMQ virtual host |
| global.config.CONTROL_PLANE_URL | string | `"http://platform-orchestrator-control-plane:8080"` | Internal URL of the control plane service |
| global.config.DATA_PLANE_URL | string | `"http://platform-orchestrator-data-plane:8080"` | Internal URL of the data plane service |
| global.config.IAM_URL | string | `"http://platform-orchestrator-iam:8080"` | Internal URL of the IAM service |
| global.config.VAULT_URL | string | `"http://openbao.openbao:8200"` | Vault URL for secret management |
| global.enableAdminApi | bool | `true` | Enable the admin API (generates a superUserToken in the secrets) |
| global.gatewayApi | object | `{"backend":{"cors":{"allowCredentials":true,"allowHeaders":["DNT","Keep-Alive","User-Agent","X-Requested-With","If-Modified-Since","Cache-Control","Content-Type","Range","Authorization","Platform-Orchestrator-User-Agent","Idempotency-Key","If-Match"],"allowMethods":["GET","POST","PUT","PATCH","DELETE","OPTIONS"],"allowOrigins":["https://*.platform-orchestrator.local"],"exposeHeaders":["Etag","Link"],"maxAge":"24h"},"extAuth":{"port":8080,"service":"platform-orchestrator-iam"},"hostname":"api.platform-orchestrator.local","http":true,"https":true,"tls":{"certificateRefs":[{"kind":"Secret","name":"api-platform-orchestrator-cert"}]}},"className":"envoy-gateway","enabled":true,"frontend":{"cors":{"allowCredentials":true,"allowMethods":["GET","POST","PUT","PATCH","DELETE","OPTIONS"],"allowOrigins":["https://*.platform-orchestrator.local"],"maxAge":"24h"},"hostname":"console.platform-orchestrator.local","http":true,"https":true,"tls":{"certificateRefs":[{"kind":"Secret","name":"console-platform-orchestrator-cert"}]}},"keycloak":{"hostname":"keycloak.platform-orchestrator.local","http":true,"https":true,"tls":{"certificateRefs":[{"kind":"Secret","name":"keycloak-platform-orchestrator-cert"}]}},"oidc":{},"useEnvoyGateway":true}` | ------------------------------------------------------------------------- Configures Kubernetes Gateway API resources (Gateways, HTTPRoutes, SecurityPolicies) for external access to the Platform Orchestrator. |
| global.gatewayApi.backend | object | `{"cors":{"allowCredentials":true,"allowHeaders":["DNT","Keep-Alive","User-Agent","X-Requested-With","If-Modified-Since","Cache-Control","Content-Type","Range","Authorization","Platform-Orchestrator-User-Agent","Idempotency-Key","If-Match"],"allowMethods":["GET","POST","PUT","PATCH","DELETE","OPTIONS"],"allowOrigins":["https://*.platform-orchestrator.local"],"exposeHeaders":["Etag","Link"],"maxAge":"24h"},"extAuth":{"port":8080,"service":"platform-orchestrator-iam"},"hostname":"api.platform-orchestrator.local","http":true,"https":true,"tls":{"certificateRefs":[{"kind":"Secret","name":"api-platform-orchestrator-cert"}]}}` | Backend (API) gateway configuration |
| global.gatewayApi.backend.cors | object | `{"allowCredentials":true,"allowHeaders":["DNT","Keep-Alive","User-Agent","X-Requested-With","If-Modified-Since","Cache-Control","Content-Type","Range","Authorization","Platform-Orchestrator-User-Agent","Idempotency-Key","If-Match"],"allowMethods":["GET","POST","PUT","PATCH","DELETE","OPTIONS"],"allowOrigins":["https://*.platform-orchestrator.local"],"exposeHeaders":["Etag","Link"],"maxAge":"24h"}` | CORS configuration for the backend gateway |
| global.gatewayApi.backend.cors.allowCredentials | bool | `true` | Allow credentials (cookies, authorization headers) |
| global.gatewayApi.backend.cors.allowHeaders | list | `["DNT","Keep-Alive","User-Agent","X-Requested-With","If-Modified-Since","Cache-Control","Content-Type","Range","Authorization","Platform-Orchestrator-User-Agent","Idempotency-Key","If-Match"]` | Allowed request headers |
| global.gatewayApi.backend.cors.allowMethods | list | `["GET","POST","PUT","PATCH","DELETE","OPTIONS"]` | Allowed HTTP methods |
| global.gatewayApi.backend.cors.allowOrigins | list | `["https://*.platform-orchestrator.local"]` | Allowed origins (supports wildcards) |
| global.gatewayApi.backend.cors.exposeHeaders | list | `["Etag","Link"]` | Headers exposed to the browser |
| global.gatewayApi.backend.cors.maxAge | string | `"24h"` | CORS preflight cache duration |
| global.gatewayApi.backend.extAuth | object | `{"port":8080,"service":"platform-orchestrator-iam"}` | External authentication configuration (Envoy Gateway only) |
| global.gatewayApi.backend.extAuth.port | int | `8080` | Service port for ext auth |
| global.gatewayApi.backend.extAuth.service | string | `"platform-orchestrator-iam"` | Service name for ext auth (IAM service) |
| global.gatewayApi.backend.hostname | string | `"api.platform-orchestrator.local"` | Hostname for the API gateway |
| global.gatewayApi.backend.http | bool | `true` | Enable HTTP listener (port 80) |
| global.gatewayApi.backend.https | bool | `true` | Enable HTTPS listener (port 443) |
| global.gatewayApi.backend.tls | object | `{"certificateRefs":[{"kind":"Secret","name":"api-platform-orchestrator-cert"}]}` | TLS configuration for the HTTPS listener |
| global.gatewayApi.backend.tls.certificateRefs | list | `[{"kind":"Secret","name":"api-platform-orchestrator-cert"}]` | Certificate references for TLS termination |
| global.gatewayApi.className | string | `"envoy-gateway"` | GatewayClass name to use |
| global.gatewayApi.enabled | bool | `true` | Enable Gateway API resource creation |
| global.gatewayApi.frontend | object | `{"cors":{"allowCredentials":true,"allowMethods":["GET","POST","PUT","PATCH","DELETE","OPTIONS"],"allowOrigins":["https://*.platform-orchestrator.local"],"maxAge":"24h"},"hostname":"console.platform-orchestrator.local","http":true,"https":true,"tls":{"certificateRefs":[{"kind":"Secret","name":"console-platform-orchestrator-cert"}]}}` | Frontend (Console) gateway configuration |
| global.gatewayApi.frontend.cors | object | `{"allowCredentials":true,"allowMethods":["GET","POST","PUT","PATCH","DELETE","OPTIONS"],"allowOrigins":["https://*.platform-orchestrator.local"],"maxAge":"24h"}` | CORS configuration for the frontend gateway |
| global.gatewayApi.frontend.hostname | string | `"console.platform-orchestrator.local"` | Hostname for the console gateway |
| global.gatewayApi.frontend.http | bool | `true` | Enable HTTP listener (port 80) |
| global.gatewayApi.frontend.https | bool | `true` | Enable HTTPS listener (port 443) |
| global.gatewayApi.frontend.tls | object | `{"certificateRefs":[{"kind":"Secret","name":"console-platform-orchestrator-cert"}]}` | TLS configuration for the HTTPS listener |
| global.gatewayApi.frontend.tls.certificateRefs | list | `[{"kind":"Secret","name":"console-platform-orchestrator-cert"}]` | Certificate references for TLS termination |
| global.gatewayApi.keycloak | object | `{"hostname":"keycloak.platform-orchestrator.local","http":true,"https":true,"tls":{"certificateRefs":[{"kind":"Secret","name":"keycloak-platform-orchestrator-cert"}]}}` | Keycloak gateway configuration |
| global.gatewayApi.keycloak.hostname | string | `"keycloak.platform-orchestrator.local"` | Hostname for the Keycloak gateway |
| global.gatewayApi.keycloak.http | bool | `true` | Enable HTTP listener (port 80) |
| global.gatewayApi.keycloak.https | bool | `true` | Enable HTTPS listener (port 443) |
| global.gatewayApi.keycloak.tls | object | `{"certificateRefs":[{"kind":"Secret","name":"keycloak-platform-orchestrator-cert"}]}` | TLS configuration for the HTTPS listener |
| global.gatewayApi.keycloak.tls.certificateRefs | list | `[{"kind":"Secret","name":"keycloak-platform-orchestrator-cert"}]` | Certificate references for TLS termination |
| global.gatewayApi.oidc | object | `{}` | OIDC provider gateway configuration (optional) If specified, exposes the built-in OIDC provider on a dedicated hostname. Set data-plane.config.OIDC_ISSUER_URL to the public URL of this gateway. |
| global.gatewayApi.useEnvoyGateway | bool | `true` | Enable Envoy Gateway-specific resources (SecurityPolicy for ext auth, CORS) |
| global.imagePullSecrets | list | `[]` | List of image pull secrets for private registries Example:   imagePullSecrets:     - name: my-registry-secret |
| global.keycloak | object | `{"database":{"host":"platform-orchestrator-cnpg-databases","name":"orchestrator-keycloak","owner":"keycloak_user","passwordSecretKey":"password","passwordSecretName":"keycloak-db-secret","port":"5432"},"realm":{"clientId":"platform-orchestrator","clientSecretName":"keycloak-client-secret","displayName":"Platform Orchestrator","name":"platform-orchestrator"}}` | ------------------------------------------------------------------------- |
| global.keycloak.database | object | `{"host":"platform-orchestrator-cnpg-databases","name":"orchestrator-keycloak","owner":"keycloak_user","passwordSecretKey":"password","passwordSecretName":"keycloak-db-secret","port":"5432"}` | Keycloak database configuration |
| global.keycloak.database.host | string | `"platform-orchestrator-cnpg-databases"` | PostgreSQL host for Keycloak |
| global.keycloak.database.name | string | `"orchestrator-keycloak"` | Database name for Keycloak |
| global.keycloak.database.owner | string | `"keycloak_user"` | Database owner/user for Keycloak |
| global.keycloak.database.passwordSecretKey | string | `"password"` | Key within the secret containing the password |
| global.keycloak.database.passwordSecretName | string | `"keycloak-db-secret"` | Secret name containing the Keycloak database password |
| global.keycloak.database.port | string | `"5432"` | PostgreSQL port for Keycloak |
| global.keycloak.realm | object | `{"clientId":"platform-orchestrator","clientSecretName":"keycloak-client-secret","displayName":"Platform Orchestrator","name":"platform-orchestrator"}` | Keycloak realm configuration |
| global.keycloak.realm.clientId | string | `"platform-orchestrator"` | OIDC client ID for the Platform Orchestrator |
| global.keycloak.realm.clientSecretName | string | `"keycloak-client-secret"` | Secret name containing the OIDC client secret |
| global.keycloak.realm.displayName | string | `"Platform Orchestrator"` | Realm display name shown in the UI |
| global.keycloak.realm.name | string | `"platform-orchestrator"` | Realm name |
| global.s3 | object | `{"adminAuth":{"secretName":"platform-orchestrator-s3-admin-credentials"}}` | ------------------------------------------------------------------------- |
| global.s3.adminAuth.secretName | string | `"platform-orchestrator-s3-admin-credentials"` | Name of the secret containing S3 admin credentials |
| global.spicedb | object | `{"database":{"host":"platform-orchestrator-cnpg-databases","name":"orchestrator-spicedb","owner":"spicedb_user","passwordSecretKey":"password","passwordSecretName":"spicedb-db-secret","port":"5432"}}` | ------------------------------------------------------------------------- |
| global.spicedb.database.host | string | `"platform-orchestrator-cnpg-databases"` | PostgreSQL host for SpiceDB |
| global.spicedb.database.name | string | `"orchestrator-spicedb"` | Database name for SpiceDB |
| global.spicedb.database.owner | string | `"spicedb_user"` | Database owner/user for SpiceDB |
| global.spicedb.database.passwordSecretKey | string | `"password"` | Key within the secret containing the password |
| global.spicedb.database.passwordSecretName | string | `"spicedb-db-secret"` | Secret name containing the SpiceDB database password |
| global.spicedb.database.port | string | `"5432"` | PostgreSQL port for SpiceDB |
| iam | object | `{"config":{"ALLOWED_GOOGLE_CLIENT_IDS":"","ALLOWED_MICROSOFT_CLIENT_IDS":"","DATABASE_HOST":"platform-orchestrator-cnpg-databases","DATABASE_NAME":"orchestrator-iam","DATABASE_PORT":"5432","KEYCLOAK_INTERNAL_URL":"http://platform-orchestrator-keycloak-service:8080","OTEL_EXPORTER_OTLP_ENDPOINT":"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317","SPICEDB_URL":"platform-orchestrator-spicedb:50051","SSO_CALLBACK_URL_PATH":"/auth/sso/callback"},"env":[{"name":"DATABASE_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"iam-db-secret"}}},{"name":"DATABASE_USER","valueFrom":{"secretKeyRef":{"key":"username","name":"iam-db-secret"}}},{"name":"AMQP_USERNAME","valueFrom":{"secretKeyRef":{"key":"username","name":"platform-orchestrator-rabbitmq-platform-user-credentials"}}},{"name":"AMQP_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"platform-orchestrator-rabbitmq-platform-user-credentials"}}},{"name":"SPICEDB_PRE_SHARED_KEY","valueFrom":{"secretKeyRef":{"key":"preshared_key","name":"spicedb-cluster-config"}}},{"name":"KEYCLOAK_CLIENT_SECRET","valueFrom":{"secretKeyRef":{"key":"clientSecret","name":"keycloak-client-secret"}}},{"name":"SSO_STATE_SECRET","valueFrom":{"secretKeyRef":{"key":"ssoStateSecret","name":"platform-orchestrator-secrets"}}},{"name":"SUPER_USER_TOKEN","valueFrom":{"secretKeyRef":{"key":"superUserToken","name":"platform-orchestrator-secrets"}}}],"gatewayApi":{"route":{"admin":{"matches":[{"path":{"type":"PathPrefix","value":"/admin/orgs"}}],"rewrite":{"path":{"replacePrefixMatch":"/internal/orgs","type":"ReplacePrefixMatch"}}},"matches":[{"path":{"type":"RegularExpression","value":"/(auth/register|auth/logout|auth/login|auth/device|auth/sso/.+|(users/.+)|(orgs/[^/]+/members)|(orgs/[^/]+/memberships.*)|(orgs/[^/]+/users/[^/]+/memberships.*)|(orgs/[^/]+/service-users.*)|(orgs/[^/]+/invitations.*)|(orgs/[^/]+/roles.*)|(orgs/[^/]+/projects/[^/]+/users.*)|(orgs/[^/]+/projects/[^/]+/envs/[^/]+/users.*)|current-user|auth/check-permissions|(devicelogins/.+))"}}]}},"image":{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-iam","tag":"v1.0.0"}}` | --------------------------------------------------------------------------- The IAM service handles authentication, authorization, SSO, user management, and role-based access control. It is deployed as a backend-module subchart. |
| iam.config | object | `{"ALLOWED_GOOGLE_CLIENT_IDS":"","ALLOWED_MICROSOFT_CLIENT_IDS":"","DATABASE_HOST":"platform-orchestrator-cnpg-databases","DATABASE_NAME":"orchestrator-iam","DATABASE_PORT":"5432","KEYCLOAK_INTERNAL_URL":"http://platform-orchestrator-keycloak-service:8080","OTEL_EXPORTER_OTLP_ENDPOINT":"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317","SPICEDB_URL":"platform-orchestrator-spicedb:50051","SSO_CALLBACK_URL_PATH":"/auth/sso/callback"}` | Configuration environment variables (injected via ConfigMap) |
| iam.config.ALLOWED_GOOGLE_CLIENT_IDS | string | `""` | Comma-separated Google OAuth client IDs for social login (leave empty to disable) |
| iam.config.ALLOWED_MICROSOFT_CLIENT_IDS | string | `""` | Comma-separated Microsoft OAuth client IDs for social login (leave empty to disable) |
| iam.config.DATABASE_HOST | string | `"platform-orchestrator-cnpg-databases"` | PostgreSQL host (should match the CNPG cluster service name) |
| iam.config.DATABASE_NAME | string | `"orchestrator-iam"` | PostgreSQL database name for IAM |
| iam.config.DATABASE_PORT | string | `"5432"` | PostgreSQL port |
| iam.config.KEYCLOAK_INTERNAL_URL | string | `"http://platform-orchestrator-keycloak-service:8080"` | Keycloak internal URL (in-cluster service URL) |
| iam.config.OTEL_EXPORTER_OTLP_ENDPOINT | string | `"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317"` | OpenTelemetry collector endpoint |
| iam.config.SPICEDB_URL | string | `"platform-orchestrator-spicedb:50051"` | SpiceDB gRPC endpoint for authorization |
| iam.config.SSO_CALLBACK_URL_PATH | string | `"/auth/sso/callback"` | SSO callback URL path |
| iam.env | list | `[{"name":"DATABASE_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"iam-db-secret"}}},{"name":"DATABASE_USER","valueFrom":{"secretKeyRef":{"key":"username","name":"iam-db-secret"}}},{"name":"AMQP_USERNAME","valueFrom":{"secretKeyRef":{"key":"username","name":"platform-orchestrator-rabbitmq-platform-user-credentials"}}},{"name":"AMQP_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"platform-orchestrator-rabbitmq-platform-user-credentials"}}},{"name":"SPICEDB_PRE_SHARED_KEY","valueFrom":{"secretKeyRef":{"key":"preshared_key","name":"spicedb-cluster-config"}}},{"name":"KEYCLOAK_CLIENT_SECRET","valueFrom":{"secretKeyRef":{"key":"clientSecret","name":"keycloak-client-secret"}}},{"name":"SSO_STATE_SECRET","valueFrom":{"secretKeyRef":{"key":"ssoStateSecret","name":"platform-orchestrator-secrets"}}},{"name":"SUPER_USER_TOKEN","valueFrom":{"secretKeyRef":{"key":"superUserToken","name":"platform-orchestrator-secrets"}}}]` | Additional environment variables (injected directly into the pod spec) Typically used for secret references |
| iam.gatewayApi | object | `{"route":{"admin":{"matches":[{"path":{"type":"PathPrefix","value":"/admin/orgs"}}],"rewrite":{"path":{"replacePrefixMatch":"/internal/orgs","type":"ReplacePrefixMatch"}}},"matches":[{"path":{"type":"RegularExpression","value":"/(auth/register|auth/logout|auth/login|auth/device|auth/sso/.+|(users/.+)|(orgs/[^/]+/members)|(orgs/[^/]+/memberships.*)|(orgs/[^/]+/users/[^/]+/memberships.*)|(orgs/[^/]+/service-users.*)|(orgs/[^/]+/invitations.*)|(orgs/[^/]+/roles.*)|(orgs/[^/]+/projects/[^/]+/users.*)|(orgs/[^/]+/projects/[^/]+/envs/[^/]+/users.*)|current-user|auth/check-permissions|(devicelogins/.+))"}}]}}` | Gateway API HTTPRoute configuration for IAM |
| iam.gatewayApi.route.admin | object | `{"matches":[{"path":{"type":"PathPrefix","value":"/admin/orgs"}}],"rewrite":{"path":{"replacePrefixMatch":"/internal/orgs","type":"ReplacePrefixMatch"}}}` | Admin API route configuration (rewrites /admin/orgs -> /internal/orgs) |
| iam.gatewayApi.route.matches | list | `[{"path":{"type":"RegularExpression","value":"/(auth/register|auth/logout|auth/login|auth/device|auth/sso/.+|(users/.+)|(orgs/[^/]+/members)|(orgs/[^/]+/memberships.*)|(orgs/[^/]+/users/[^/]+/memberships.*)|(orgs/[^/]+/service-users.*)|(orgs/[^/]+/invitations.*)|(orgs/[^/]+/roles.*)|(orgs/[^/]+/projects/[^/]+/users.*)|(orgs/[^/]+/projects/[^/]+/envs/[^/]+/users.*)|current-user|auth/check-permissions|(devicelogins/.+))"}}]` | Path matching rules for IAM API endpoints (auth, users, roles, etc.) |
| iam.image | object | `{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-iam","tag":"v1.0.0"}` | Container image for IAM |
| iam.image.repository | string | `"ghcr.io/stellwerk-labs/platform-orchestrator-iam"` | Image repository. Prepend repository hostname and path as per your setup, e.g. `my-registry.example.com/orchestrator/platform-orchestrator-iam` |
| iam.image.tag | string | `"v1.0.0"` | Image tag |
| keycloak | object | `{"enabled":true}` | Keycloak subchart (identity provider) |
| keycloak.enabled | bool | `true` | Enable the in-cluster Keycloak |
| rabbitmq | object | `{"enabled":true}` | RabbitMQ subchart |
| rabbitmq.enabled | bool | `true` | Enable the in-cluster RabbitMQ broker (disable to use external AMQP) |
| seaweed | object | `{"enabled":true,"image":{"tag":"4.07"}}` | SeaweedFS subchart (S3-compatible storage for runner logs) |
| seaweed.enabled | bool | `true` | Enable the in-cluster SeaweedFS (disable to use external S3) |
| seaweed.image.tag | string | `"4.07"` | SeaweedFS image tag |
| spicedb | object | `{"enabled":true}` | SpiceDB subchart (authorization engine) |
| spicedb.enabled | bool | `true` | Enable the in-cluster SpiceDB |

<!-- SUBCHART_VALUES_START -->
<!-- SUBCHART_VALUES_END -->

## Environment Variables from Secrets

Each backend service and the console can have secrets injected as environment
variables via `env` (individual `secretKeyRef` entries) or `envFromSecrets`
(entire secrets mounted as env vars). Both are fully overridable in your values
file. The tables below document the **default** configuration.

### Control Plane (`control-plane.env`)

| Env Var | Default Secret Name | Secret Key | Description |
|---------|---------------------|------------|-------------|
| `DATABASE_USER` | `controlplane-db-secret` | `username` | PostgreSQL username |
| `DATABASE_PASSWORD` | `controlplane-db-secret` | `password` | PostgreSQL password |
| `AMQP_USERNAME` | `platform-orchestrator-rabbitmq-platform-user-credentials` | `username` | RabbitMQ username |
| `AMQP_PASSWORD` | `platform-orchestrator-rabbitmq-platform-user-credentials` | `password` | RabbitMQ password |

### Data Plane (`data-plane.env`)

| Env Var | Default Secret Name | Secret Key | Description |
|---------|---------------------|------------|-------------|
| `DATABASE_USER` | `dataplane-db-secret` | `username` | PostgreSQL username |
| `DATABASE_PASSWORD` | `dataplane-db-secret` | `password` | PostgreSQL password |
| `AMQP_USERNAME` | `platform-orchestrator-rabbitmq-platform-user-credentials` | `username` | RabbitMQ username |
| `AMQP_PASSWORD` | `platform-orchestrator-rabbitmq-platform-user-credentials` | `password` | RabbitMQ password |
| `RUNNER_TOKEN_SALT` | `platform-orchestrator-secrets` | `runnerTokenSalt` | Salt for runner authentication tokens |
| `RUNNER_LOGS_BUCKET_CREDS` | `platform-orchestrator-s3-admin-credentials` | `credentials_json` | S3 credentials for runner log storage |

### IAM (`iam.env`)

| Env Var | Default Secret Name | Secret Key | Description |
|---------|---------------------|------------|-------------|
| `DATABASE_USER` | `iam-db-secret` | `username` | PostgreSQL username |
| `DATABASE_PASSWORD` | `iam-db-secret` | `password` | PostgreSQL password |
| `AMQP_USERNAME` | `platform-orchestrator-rabbitmq-platform-user-credentials` | `username` | RabbitMQ username |
| `AMQP_PASSWORD` | `platform-orchestrator-rabbitmq-platform-user-credentials` | `password` | RabbitMQ password |
| `SPICEDB_PRE_SHARED_KEY` | `spicedb-cluster-config` | `preshared_key` | SpiceDB pre-shared authentication key |
| `KEYCLOAK_CLIENT_SECRET` | `keycloak-client-secret` | `clientSecret` | Keycloak OIDC client secret |
| `SENDGRID_API_KEY` | | | SendGrid API key to enable email invitations (disabled by default) |
| `SSO_STATE_SECRET` | `platform-orchestrator-secrets` | `ssoStateSecret` | Secret for SSO state parameter signing |
| `SUPER_USER_TOKEN` | `platform-orchestrator-secrets` | `superUserToken` | Admin API authentication token |
| `WORKOS_API_KEY` | | | WorkOS API key to enable SSO (disabled by default) |
| `WORKOS_CLIENT_ID` | | | WorkOS client ID to enable SSO (disabled by default) |

### Console

The console does not inject secrets via `env` by default. Use `console.envFromSecrets`
to mount additional secrets as environment variables if needed.

## Secrets

All secrets are **auto-generated** by the chart (or its subcharts) on first install and preserved across upgrades. No pre-existing secrets are required.

| Secret Name | Keys | Created By | Used By |
|-------------|------|------------|---------|
| `postgres-admin-secret` | `username`, `password` | cnpg-databases | CNPG cluster admin |
| `controlplane-db-secret` | `username`, `password` | cnpg-databases | Control Plane |
| `dataplane-db-secret` | `username`, `password` | cnpg-databases | Data Plane |
| `iam-db-secret` | `username`, `password` | cnpg-databases | IAM |
| `spicedb-db-secret` | `username`, `password` | cnpg-databases | SpiceDB |
| `keycloak-db-secret` | `username`, `password` | cnpg-databases | Keycloak |
| `spicedb-cluster-config` | `preshared_key`, `datastore_uri` | spicedb | SpiceDB, IAM |
| `keycloak-bootstrap-admin` | `username`, `password` | keycloak | Keycloak |
| `keycloak-client-secret` | `clientSecret` | keycloak | Keycloak, IAM |
| `platform-orchestrator-rabbitmq-platform-user-credentials` | `username`, `password` | RabbitMQ Operator (via User CRD) | Control Plane, Data Plane, IAM |
| `platform-orchestrator-s3-admin-credentials` | `access_key_id`, `secret_access_key`, `credentials_json` | seaweed | Data Plane |
| `s3-secret` | `config` | seaweed | SeaweedFS Filer |
| `platform-orchestrator-secrets` | `runnerTokenSalt`, `ssoStateSecret`, `superUserToken` | parent chart | Data Plane, IAM |
