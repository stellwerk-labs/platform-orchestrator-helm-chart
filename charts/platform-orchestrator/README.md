# platform-orchestrator

Platform Orchestrator

Chart `0.7.0` adds Module Version Management, including immutable versions,
lifecycle history and Environment Pins. It pins the coordinated application
components by digest and retains the existing Casbin IAM, HTTPS Runner Gateway
and NATS JetStream architecture. See the [release notes](../../docs/releases/v0.7.0.md)
for the component versions, breaking authoring changes and recovery limits.

## Architecture

The chart deploys the following components:

| Component | Subchart | Description |
|-----------|----------|-------------|
| **Control Plane** | `backend-module` (alias) | Manages orgs, projects, environments, modules, and runners |
| **Data Plane** | `backend-module` (alias) | Handles deployments, active resources, and logs |
| **IAM** | `backend-module` (alias) | Authentication, authorization, SSO, and user management |
| **Console** | `console` | Web-based UI |
| **PostgreSQL** | `cnpg-databases` | CloudNativePG-managed PostgreSQL cluster |
| **NATS JetStream** | `nats` | Durable command and event broker |
| **Runner gateway** | runner image | Outbound HTTPS interface for agents and deployment Jobs |
| **Keycloak** | `keycloak` | Identity provider and SSO |

## Native plugin configuration

The `control-plane.configurationProfiles.nativePluginEntitlements`
profile is disabled by default and does not enable a plugin. When explicitly
enabled alongside the native gateway, it mounts a public issuer trust document
and signed offline licence bundle into Core. It never mounts an issuer private
key and does not send these documents to the plugin, Data Plane, IAM or Console.
Production mode rejects development trust. Development-mode installations must
explicitly select `PLUGIN_ENTITLEMENT_MODE: development`.

The existing `secretFiles` adapter uses read-only single-file `subPath` mounts.
Keep the `/etc/stellwerk/entitlements` paths: the strict Core reader rejects
symlinks, including projected-Secret directory paths and common `/var/run`
aliases. Use versioned Secret names and roll Core after a trust or bundle
change; `subPath` mounts do not refresh in place. Secrets contain only public
issuer keys and signed documents, never the signing key. Expiry and revocation
stop new work while preserving previously activated read and recovery access
under the existing permissions.

IAM authorises the Plugin Manager API. Name its operators as comma-separated
user IDs in `iam.config.PLUGIN_MANAGER_WRITERS` (manage plugins, includes read)
and `iam.config.PLUGIN_MANAGER_READERS` (read only). Both are empty by default,
so nobody can manage plugins until they are set. IAM refuses to start if either
lists a service user.

Plugin pages also require an operator-reviewed Console CSP allowance. Set
`console.gatewayApi.route.pluginUiOrigins` to the exact HTTPS origins declared
by the installed plugins, for example `["https://addons.example.com"]`.
The default empty list preserves the stock policy. Entries use separate DNS
hostnames and optional non-default ports; wildcards, credentials, paths, query
strings, fragments, duplicate origins and the Console hostname are rejected.
This grants framing only, without adding script or network permissions. Each
plugin runtime must independently restrict `frame-ancestors` to the Console
origin, and the host still validates every bridge message and operation.

Plugin UIs must also stay outside the API's credentialed scope, so that only
the Console can act with the user's session. IAM sets the session cookie with
`Domain=` the API hostname (`global.gatewayApi.backend.hostname`), which sends
it to that hostname and every subdomain, and the API's CORS policy answers the
origins in `global.gatewayApi.backend.cors.allowOrigins` with credentials
(`allowCredentials: true` by default). The chart therefore rejects a plugin UI origin on the API hostname or one of its
subdomains (any port), and a plugin UI origin that an `allowOrigins` entry
matches. Envoy Gateway turns each `*` of an entry into the regex `.*` and
matches the whole origin, so the default `https://*.platform-orchestrator.local`
admits every HTTPS origin under that domain without a port. Before adding plugin
UI origins, list the exact Console origins, for example:

```yaml
global:
  gatewayApi:
    backend:
      hostname: api.example.com
      cors:
        allowOrigins: ["https://console.example.com"]
    frontend:
      hostname: console.example.com
console:
  gatewayApi:
    route:
      pluginUiOrigins: ["https://rollouts.example-addons.com"]
```

A separate registrable domain for plugin UIs, as above, also keeps them from
setting cookies for a parent domain they would share with the API. The CORS
default stays unchanged for installations without plugin UIs.

## Plugin workload identity (v1alpha)

Plugin workloads authenticate to Core with short-lived IAM tokens obtained by
exchanging their projected Kubernetes ServiceAccount token, not with static
service-user tokens. The exchange is off by default and the chart then renders
no IAM configuration or RBAC for it. Enabling it needs an IAM image that
contains the v1alpha workload token exchange.

1. Enable `iam.configurationProfiles.pluginWorkloadIdentity` and set
   `PLUGIN_WORKLOAD_TOKEN_ISSUER` to the cluster's ServiceAccount issuer, the
   `issuer` field of `kubectl get --raw /.well-known/openid-configuration`.
   Set `PLUGIN_WORKLOAD_BINDING_WRITERS` to the IAM principal ID of the
   installation controller. Only listed principals hold the platform-level
   permission `plugin_workload_binding_write`; organization roles cannot grant
   it. IAM reads `https://kubernetes.default.svc/openid/v1/jwks` with its own
   ServiceAccount token and the cluster CA. The chart mounts that token and
   binds IAM's ServiceAccount to the built-in read-only ClusterRole
   `system:service-account-issuer-discovery`, which Kubernetes also grants to
   all ServiceAccounts by default; nothing else is granted.
2. The plugin's identity is a platform principal: an IAM service user that
   belongs to no organization and holds no roles, so one principal serves every
   organization enabled for the installation. Create it together with its
   binding in step 3. Service users that hold roles get no workload
   credential, and organization service users cannot be bound. A principal
   with a static token for the Data Plane admission checker is managed under
   `/platform-principals` by holders of `plugin_workload_binding_write`.
3. As the installation controller, create the binding with
   `POST /plugin-workload-bindings` and `issuer`, `namespace`,
   `service_account`, `audience`, `platform_principal` (`display_name`; or
   `service_user_id` of an existing unbound platform principal), `plugin_id`
   and `installation_id`, the UUID Core assigned with
   `POST /plugin-installations`. A ServiceAccount and a service user each
   have at most one binding. `DELETE /plugin-workload-bindings/{bindingId}`
   revokes it; the next request with any token issued for it fails, and the
   principal stays so a new binding can name it. Only
   then record the principal on the installation with
   `PUT /plugin-installations/{id}/identity`: Core refuses it with
   `409 plugin_workload_binding_missing` unless IAM binds exactly that plugin
   ID, installation UUID and platform principal.
4. Run the plugin runtime under exactly that ServiceAccount with a projected
   token volume whose `audience` equals the binding's `audience` (and no other
   audience) and whose `expirationSeconds` is at most 600. The runtime posts it
   to `POST /auth/plugin-workload-token` (RFC 8693 field names) and sends the
   returned `PWT-` token as `Authorization: Bearer`. Tokens are valid for at
   most `PLUGIN_WORKLOAD_TOKEN_TTL` (15 minutes) and never longer than the
   projected token; a deleted Pod's token stays valid until it expires.

Where IAM cannot reach the API server, export the key set with
`kubectl get --raw /openid/v1/jwks`, store it as `jwks.json` in a Secret,
enable `iam.configurationProfiles.pluginWorkloadStaticJWKS` with that Secret
name and set `serviceAccountIssuerDiscovery: false`. The file is a `subPath`
mount: roll IAM after the cluster rotates its signing keys.
`PLUGIN_WORKLOAD_STATIC_TOKEN_ADAPTER: v1alpha` keeps static tokens of bound
service users usable during a migration only; leave it empty in production.

## Ordinary Deployment admission

The Data Plane can ask Core to guard each ordinary Deployment against
concurrent Pin changes before it commits it. Both profiles are off by default;
enable them together:

1. As a holder of `plugin_workload_binding_write`, create an IAM platform
   principal with a static token (`POST /platform-principals`), or reuse the
   plugin admission checker. It belongs to no organization, so one principal
   serves every organization.
2. Store its token as `core-bearer-token` in a Secret and enable
   `data-plane.configurationProfiles.deploymentAdmission` with that Secret and
   the authenticated HTTPS backend Gateway origin.
3. Enable `control-plane.configurationProfiles.deploymentAdmission` with the
   principal's UUID.

```yaml
control-plane:
  configurationProfiles:
    deploymentAdmission:
      enabled: true
      config:
        DEPLOYMENT_ADMISSION_IDENTITY: "<data-plane-principal-uuid>"
data-plane:
  configurationProfiles:
    deploymentAdmission:
      enabled: true
      config:
        DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL: https://api.example.com
      secretFiles:
        - name: deployment-admission-core-token
          secretName: data-plane-admission-token-v1
          key: core-bearer-token
          mountPath: /var/run/secrets/stellwerk/deployment-admission/core-bearer-token
```

Core admits Deployments of every organization as this one identity, including
organizations created later, so a new organization needs no change here and no
restart. Core asks IAM on every callback and refuses any other identity with
`403 deployment_admission_service_forbidden`. The token is a `subPath` mount:
use a versioned Secret name and roll the Data Plane after a token rotation.

## Prerequisites

- Kubernetes 1.27+
- Helm 3.x
- [cert-manager](https://cert-manager.io/) (for TLS certificates)
- [Gateway API CRDs](https://gateway-api.sigs.k8s.io/) and a gateway controller (e.g., Envoy Gateway)
- [CloudNativePG Operator](https://cloudnative-pg.io/) (if using the in-cluster PostgreSQL)
- OpenBao (external dependency, Vault-compatible)

## Installation

```bash
helm install platform-orchestrator ./charts/platform-orchestrator \
  --namespace platform-orchestrator \
  --create-namespace \
  -f my-values.yaml
```

Upgrading from a SpiceDB-based installation causes a short IAM outage. The IAM
Deployment uses `Recreate`, and its first replacement Pod serializes, resumes,
and verifies the database migration before becoming ready. Back up PostgreSQL
and read the [upgrade procedure](../../docs/migrations/spicedb-to-casbin.md)
before upgrading from a SpiceDB-based release.

The generated shared NATS token is for local bootstrap. Production deployments
should supply scoped internal service credentials with a defined issuance,
rotation, and revocation process. Runners receive only HTTPS credentials.

The NATS bootstrap Job creates or updates the JetStream streams and object
stores. It belongs to the release: the completed Job stays, and Helm replaces
it when the chart version or the Job's settings change. To run it again with
unchanged settings, for example after it failed or after NATS lost its
storage, delete the Job and run `helm upgrade` again.

Each backend renders one Service at its existing name. `service.createHeadless`
selects headless mode (`type: ClusterIP`, `clusterIP: None`) for that Service;
it does not create an additional Service. The Data Plane enables this by
default, retaining its configured headless DNS name. With the flag disabled,
the Service uses `service.type` normally. Changing mode on an existing Service
requires an explicit operator-managed migration because Kubernetes does not
allow its primary `clusterIP` to change in place. The chart does not delete or
recreate Services automatically.

Set `data-plane.config.RUNNER_GATEWAY_URL` to the public HTTPS URL that ECS and
other runners outside the cluster can reach. Keep
`RUNNER_GATEWAY_INTERNAL_URL` on the namespace-qualified gateway Service for
Kubernetes Jobs created inside this cluster. A short Service name resolves in
the Job's namespace, which need not be the Orchestrator namespace. The default
assumes release and namespace `platform-orchestrator`; override it with
`http://<gateway-service>.<orchestrator-namespace>.svc:8080/runner-gateway` for
another installation. When the API hostname changes, update the public runner
gateway URL with it.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cnpg-databases | object | `{"enabled":true}` | CNPG PostgreSQL databases subchart |
| cnpg-databases.admin | object | `{"passwordSecretKey":"password","passwordSecretName":"postgres-admin-secret","username":"postgres"}` | Initial admin/superuser credentials |
| cnpg-databases.admin.passwordSecretKey | string | `"password"` | Key within the secret containing the password |
| cnpg-databases.admin.passwordSecretName | string | `"postgres-admin-secret"` | Secret name containing the superuser password |
| cnpg-databases.admin.username | string | `"postgres"` | Superuser username |
| cnpg-databases.cluster | object | `{"instances":1,"storageClass":"standard","storageSize":"1Gi"}` | Cluster settings |
| cnpg-databases.cluster.instances | int | `1` | Number of PostgreSQL instances |
| cnpg-databases.cluster.storageClass | string | `"standard"` | Storage class name |
| cnpg-databases.cluster.storageSize | string | `"1Gi"` | PVC storage size per instance |
| cnpg-databases.databases | list | `[{"name":"orchestrator-controlplane","owner":"controlplane_user","passwordSecretKey":"password","passwordSecretName":"controlplane-db-secret"},{"name":"orchestrator-dataplane","owner":"dataplane_user","passwordSecretKey":"password","passwordSecretName":"dataplane-db-secret"},{"name":"orchestrator-iam","owner":"iam_user","passwordSecretKey":"password","passwordSecretName":"iam-db-secret"}]` | List of databases to create |
| cnpg-databases.enabled | bool | `true` | Enable the in-cluster PostgreSQL database (disable to use external DB) |
| cnpg-databases.postgresql | object | `{"logStatement":"all","maxConnections":"100","sharedBuffers":"256MB"}` | PostgreSQL server parameters |
| cnpg-databases.postgresql.logStatement | string | `"all"` | Statement logging level (none, ddl, mod, all) |
| cnpg-databases.postgresql.maxConnections | string | `"100"` | Maximum number of concurrent connections |
| cnpg-databases.postgresql.sharedBuffers | string | `"256MB"` | Shared buffer size |
| console | object | `{"config":{"CONFIG_CAT_SDK_KEY":"","DATADOG_CLIENT_TOKEN":"","DEPLOYMENT_MODE":"self-hosted","GOOGLE_CLIENT_ID":"","MICROSOFT_CLIENT_ID":""},"image":{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-frontend","tag":"v1.4.0-rc.4@sha256:9bb61c142e21cfc92e45ac07f614e65e326510caffe047e34a78901fad9210c5"}}` | --------------------------------------------------------------------------- The web-based UI for the Platform Orchestrator. |
| console.affinity | object | `{}` | Pod affinity rules |
| console.config | object | `{"CONFIG_CAT_SDK_KEY":"","DATADOG_CLIENT_TOKEN":"","DEPLOYMENT_MODE":"self-hosted","GOOGLE_CLIENT_ID":"","MICROSOFT_CLIENT_ID":""}` | Configuration environment variables (injected via ConfigMap) |
| console.config.CONFIG_CAT_SDK_KEY | string | `""` | ConfigCat SDK key for feature flags (leave empty to disable) |
| console.config.DATADOG_CLIENT_TOKEN | string | `""` | Datadog client token for RUM monitoring (leave empty to disable) |
| console.config.DEPLOYMENT_MODE | string | `"self-hosted"` | Deployment mode identifier |
| console.config.ENVIRONMENT_NAME | string | `"production"` | Environment name |
| console.config.GOOGLE_CLIENT_ID | string | `""` | Google OAuth client ID for social login button (leave empty to hide) |
| console.config.MICROSOFT_CLIENT_ID | string | `""` | Microsoft OAuth client ID for social login button (leave empty to hide) |
| console.envFromSecrets | list | `[]` | Names of secrets to load as environment variables via envFrom |
| console.gatewayApi | object | `{"route":{"matches":[{"path":{"type":"PathPrefix","value":"/"}}],"pluginUiOrigins":[]}}` | Gateway API HTTPRoute configuration (created when global Gateway API is enabled) |
| console.gatewayApi.route.pluginUiOrigins | list | `[]` | Exact HTTPS plugin UI origins allowed by Console CSP frame-src. Use separate DNS hostnames and optional non-default ports; wildcards, credentials, paths, queries, fragments, and duplicate origins are rejected, as are the Console hostname, the API hostname and its subdomains (they receive the session cookie) and origins that `global.gatewayApi.backend.cors.allowOrigins` matches. Empty keeps the stock policy. |
| console.image | object | `{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-frontend","tag":"v1.4.0-rc.4@sha256:9bb61c142e21cfc92e45ac07f614e65e326510caffe047e34a78901fad9210c5"}` | Container image for the console |
| console.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| console.image.repository | string | `"ghcr.io/stellwerk-labs/platform-orchestrator-frontend"` | Image repository. Prepend repository hostname and path as per your setup, e.g. `my-registry.example.com/orchestrator/platform-orchestrator-frontend` |
| console.image.tag | string | `"v1.4.0-rc.4@sha256:9bb61c142e21cfc92e45ac07f614e65e326510caffe047e34a78901fad9210c5"` | Image tag |
| console.nodeSelector | object | `{}` | Node selector constraints |
| console.podAnnotations | object | `{}` | Additional pod annotations |
| console.podLabels | object | `{}` | Additional pod labels |
| console.podSecurityContext | object | `{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context |
| console.replicaCount | int | `1` | Number of replicas |
| console.resources | object | `{}` | CPU/memory resource requests and limits |
| console.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}` | Container-level security context |
| console.service | object | `{"port":9000,"type":"ClusterIP"}` | Service configuration |
| console.service.port | int | `9000` | Service port |
| console.service.type | string | `"ClusterIP"` | Service type |
| console.tolerations | list | `[]` | Pod tolerations |
| control-plane | object | `{"config":{"DATABASE_HOST":"platform-orchestrator-cnpg-databases","DATABASE_NAME":"orchestrator-controlplane","DATABASE_PORT":"5432","NATS_URL":"nats://platform-orchestrator-nats:4222","OTEL_EXPORTER_OTLP_ENDPOINT":"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317","VAULT_AUTH":"kubernetes:platform-orchestrator-control-plane:platform-orchestrator","VAULT_ROLE":"orchestrator-control-plane"},"configurationProfiles":{"deploymentAdmission":{"config":{"DEPLOYMENT_ADMISSION_IDENTITY":""},"enabled":false,"requiredConfig":["DEPLOYMENT_ADMISSION_IDENTITY"]},"nativePluginEntitlements":{"config":{"PLUGIN_ENTITLEMENT_MODE":"production","PLUGIN_ENTITLEMENT_TRUST_FILE":"/etc/stellwerk/entitlements/trust.json"},"enabled":false,"secretFiles":[{"key":"trust.json","mountPath":"/etc/stellwerk/entitlements/trust.json","name":"native-plugin-entitlement-trust","secretName":""}]},"nativePluginGateway":{"config":{"PLUGIN_CA_FILE":"/var/run/secrets/stellwerk/plugins/plugin-ca.pem","PLUGIN_DATA_PLANE_INTERNAL_HTTP":"false","PLUGIN_DEVELOPMENT_HTTP":"false","PLUGIN_HOST_ENABLED":"true","PLUGIN_ISSUER":"stellwerk-control-plane","PLUGIN_SIGNING_KEY_FILE":"/var/run/secrets/stellwerk/plugins/signing-key.pem"},"enabled":false,"secretFiles":[{"key":"signing-key.pem","mountPath":"/var/run/secrets/stellwerk/plugins/signing-key.pem","name":"native-plugin-signing-key","secretName":""},{"key":"plugin-ca.pem","mountPath":"/var/run/secrets/stellwerk/plugins/plugin-ca.pem","name":"native-plugin-ca","secretName":""}]}},"env":[{"name":"DATABASE_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"controlplane-db-secret"}}},{"name":"DATABASE_USER","valueFrom":{"secretKeyRef":{"key":"username","name":"controlplane-db-secret"}}},{"name":"NATS_TOKEN","valueFrom":{"secretKeyRef":{"key":"natsAuthToken","name":"platform-orchestrator-secrets"}}}],"gatewayApi":{"route":{"admin":{"matches":[{"path":{"type":"PathPrefix","value":"/admin/orgs"}}],"rewrite":{"path":{"replacePrefixMatch":"/internal/orgs","type":"ReplacePrefixMatch"}}},"matches":[{"path":{"type":"RegularExpression","value":"/orgs($|/[^/]+($|/(envs|env-types|resource-types|module-providers|runners|runner-rules|modules|module-rules|module-catalogue|module-version-pins|module-version-lifecycle-transactions)($|/.*)|/plugins($|/[^/]+($|/invoke))|/projects($|/[^/]+($|/envs($|/[^/]+($|/(actions/refresh_runner|available-resource-types|deletion-impact)$))))))"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/module-versions/proposed$"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/deployment-admissions/[^/]+(/(settle|seal-absence))?$"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/projects/[^/]+/envs/[^/]+/deployments/[^/]+/actions/acknowledge-outcome$"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/plugins/[^/]+/(entitlement|inventory|deployment-reads|authorization-checks|operations/[^/]+(/(modules|authorize|control|check|inventory|resource-events|events|pins(/receipts/[^/]+)?|deployments(/[^/]+/reconcile)?))?)$"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/plugins/[^/]+/projects/[^/]+/envs/[^/]+/deployments/[^/]+/(logs|outputs)$"}},{"path":{"type":"RegularExpression","value":"^/(plugin-packages|plugin-installations(/[^/]+(/(identity|upgrade|organization-mode|actions/[^/]+|organizations/[^/]+))?)?|plugin-entitlement-bundles|plugin-audit-events)$"}}]}},"image":{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-cp","tag":"v3.1.0-rc.2@sha256:88ec47df97767592d310173bcd1f9ce9885ac25deb4f0db009364dd1881d66af"},"serviceAccount":{"allowCreateToken":true}}` | --------------------------------------------------------------------------- The control plane manages organizations, projects, environments, modules, and runners. It is deployed as a backend-module subchart. |
| control-plane.affinity | object | `{}` | Pod affinity rules |
| control-plane.config | object | `{"DATABASE_HOST":"platform-orchestrator-cnpg-databases","DATABASE_NAME":"orchestrator-controlplane","DATABASE_PORT":"5432","NATS_URL":"nats://platform-orchestrator-nats:4222","OTEL_EXPORTER_OTLP_ENDPOINT":"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317","VAULT_AUTH":"kubernetes:platform-orchestrator-control-plane:platform-orchestrator","VAULT_ROLE":"orchestrator-control-plane"}` | Configuration environment variables (injected via ConfigMap) |
| control-plane.config.DATABASE_HOST | string | `"platform-orchestrator-cnpg-databases"` | PostgreSQL host (should match the CNPG cluster service name) |
| control-plane.config.DATABASE_NAME | string | `"orchestrator-controlplane"` | PostgreSQL database name for the control plane |
| control-plane.config.DATABASE_PORT | string | `"5432"` | PostgreSQL port |
| control-plane.config.NATS_URL | string | `"nats://platform-orchestrator-nats:4222"` | NATS endpoint used for durable service events |
| control-plane.config.OTEL_EXPORTER_OTLP_ENDPOINT | string | `"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317"` | OpenTelemetry collector endpoint |
| control-plane.config.VAULT_AUTH | string | `"kubernetes:platform-orchestrator-control-plane:platform-orchestrator"` | Vault authentication string Format: "kubernetes:<service account name>:<audience1>,<audience2>" |
| control-plane.config.VAULT_ROLE | string | `"orchestrator-control-plane"` | Vault role for the control plane |
| control-plane.configurationProfiles | object | `{"deploymentAdmission":{"config":{"DEPLOYMENT_ADMISSION_IDENTITY":""},"enabled":false,"requiredConfig":["DEPLOYMENT_ADMISSION_IDENTITY"]},"nativePluginEntitlements":{"config":{"PLUGIN_ENTITLEMENT_MODE":"production","PLUGIN_ENTITLEMENT_TRUST_FILE":"/etc/stellwerk/entitlements/trust.json"},"enabled":false,"secretFiles":[{"key":"trust.json","mountPath":"/etc/stellwerk/entitlements/trust.json","name":"native-plugin-entitlement-trust","secretName":""}]},"nativePluginGateway":{"config":{"PLUGIN_CA_FILE":"/var/run/secrets/stellwerk/plugins/plugin-ca.pem","PLUGIN_DATA_PLANE_INTERNAL_HTTP":"false","PLUGIN_DEVELOPMENT_HTTP":"false","PLUGIN_HOST_ENABLED":"true","PLUGIN_ISSUER":"stellwerk-control-plane","PLUGIN_SIGNING_KEY_FILE":"/var/run/secrets/stellwerk/plugins/signing-key.pem"},"enabled":false,"secretFiles":[{"key":"signing-key.pem","mountPath":"/var/run/secrets/stellwerk/plugins/signing-key.pem","name":"native-plugin-signing-key","secretName":""},{"key":"plugin-ca.pem","mountPath":"/var/run/secrets/stellwerk/plugins/plugin-ca.pem","name":"native-plugin-ca","secretName":""}]}}` | Optional Control Plane profiles. Each is inert until an operator enables it and supplies its settings and referenced Secrets. |
| control-plane.configurationProfiles.deploymentAdmission | object | `{"config":{"DEPLOYMENT_ADMISSION_IDENTITY":""},"enabled":false,"requiredConfig":["DEPLOYMENT_ADMISSION_IDENTITY"]}` | Ordinary Deployment admission: Core guards each ordinary Deployment against concurrent Pin changes before the Data Plane commits it. Set `DEPLOYMENT_ADMISSION_IDENTITY` to the UUID of the Data Plane's IAM platform principal with a static token. The one identity serves every organization, including organizations created later, so adding an organization needs no change here. Enable together with `data-plane.configurationProfiles.deploymentAdmission`. |
| control-plane.configurationProfiles.nativePluginEntitlements | object | `{"config":{"PLUGIN_ENTITLEMENT_MODE":"production","PLUGIN_ENTITLEMENT_TRUST_FILE":"/etc/stellwerk/entitlements/trust.json"},"enabled":false,"secretFiles":[{"key":"trust.json","mountPath":"/etc/stellwerk/entitlements/trust.json","name":"native-plugin-entitlement-trust","secretName":""}]}` | Offline licence trust is consumed only by Core. This profile does not enable plugins or grant IAM rights. The issuer's private key is never mounted. Only the trust file is mounted: licence bundles are imported through the Plugin Manager API. Use a versioned Secret and restart Core when replacing trust. |
| control-plane.configurationProfiles.nativePluginGateway | object | `{"config":{"PLUGIN_CA_FILE":"/var/run/secrets/stellwerk/plugins/plugin-ca.pem","PLUGIN_DATA_PLANE_INTERNAL_HTTP":"false","PLUGIN_DEVELOPMENT_HTTP":"false","PLUGIN_HOST_ENABLED":"true","PLUGIN_ISSUER":"stellwerk-control-plane","PLUGIN_SIGNING_KEY_FILE":"/var/run/secrets/stellwerk/plugins/signing-key.pem"},"enabled":false,"secretFiles":[{"key":"signing-key.pem","mountPath":"/var/run/secrets/stellwerk/plugins/signing-key.pem","name":"native-plugin-signing-key","secretName":""},{"key":"plugin-ca.pem","mountPath":"/var/run/secrets/stellwerk/plugins/plugin-ca.pem","name":"native-plugin-ca","secretName":""}]}` | Native plugin gateway configuration. The signing key remains private to Core; plugin runtimes receive only its public key. |
| control-plane.env | list | `[{"name":"DATABASE_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"controlplane-db-secret"}}},{"name":"DATABASE_USER","valueFrom":{"secretKeyRef":{"key":"username","name":"controlplane-db-secret"}}},{"name":"NATS_TOKEN","valueFrom":{"secretKeyRef":{"key":"natsAuthToken","name":"platform-orchestrator-secrets"}}}]` | Additional environment variables (injected directly into the pod spec) Typically used for secret references |
| control-plane.envFromSecrets | list | `[]` | Names of secrets to load as environment variables via envFrom |
| control-plane.gatewayApi | object | `{"route":{"admin":{"matches":[{"path":{"type":"PathPrefix","value":"/admin/orgs"}}],"rewrite":{"path":{"replacePrefixMatch":"/internal/orgs","type":"ReplacePrefixMatch"}}},"matches":[{"path":{"type":"RegularExpression","value":"/orgs($|/[^/]+($|/(envs|env-types|resource-types|module-providers|runners|runner-rules|modules|module-rules|module-catalogue|module-version-pins|module-version-lifecycle-transactions)($|/.*)|/plugins($|/[^/]+($|/invoke))|/projects($|/[^/]+($|/envs($|/[^/]+($|/(actions/refresh_runner|available-resource-types|deletion-impact)$))))))"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/module-versions/proposed$"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/deployment-admissions/[^/]+(/(settle|seal-absence))?$"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/projects/[^/]+/envs/[^/]+/deployments/[^/]+/actions/acknowledge-outcome$"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/plugins/[^/]+/(entitlement|inventory|deployment-reads|authorization-checks|operations/[^/]+(/(modules|authorize|control|check|inventory|resource-events|events|pins(/receipts/[^/]+)?|deployments(/[^/]+/reconcile)?))?)$"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/plugins/[^/]+/projects/[^/]+/envs/[^/]+/deployments/[^/]+/(logs|outputs)$"}},{"path":{"type":"RegularExpression","value":"^/(plugin-packages|plugin-installations(/[^/]+(/(identity|upgrade|organization-mode|actions/[^/]+|organizations/[^/]+))?)?|plugin-entitlement-bundles|plugin-audit-events)$"}}]}}` | Gateway API HTTPRoute configuration for the control plane |
| control-plane.gatewayApi.route.admin | object | `{"matches":[{"path":{"type":"PathPrefix","value":"/admin/orgs"}}],"rewrite":{"path":{"replacePrefixMatch":"/internal/orgs","type":"ReplacePrefixMatch"}}}` | Admin API route configuration (rewrites /admin/orgs -> /internal/orgs) |
| control-plane.gatewayApi.route.matches | list | `[{"path":{"type":"RegularExpression","value":"/orgs($|/[^/]+($|/(envs|env-types|resource-types|module-providers|runners|runner-rules|modules|module-rules|module-catalogue|module-version-pins|module-version-lifecycle-transactions)($|/.*)|/plugins($|/[^/]+($|/invoke))|/projects($|/[^/]+($|/envs($|/[^/]+($|/(actions/refresh_runner|available-resource-types|deletion-impact)$))))))"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/module-versions/proposed$"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/deployment-admissions/[^/]+(/(settle|seal-absence))?$"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/projects/[^/]+/envs/[^/]+/deployments/[^/]+/actions/acknowledge-outcome$"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/plugins/[^/]+/(entitlement|inventory|deployment-reads|authorization-checks|operations/[^/]+(/(modules|authorize|control|check|inventory|resource-events|events|pins(/receipts/[^/]+)?|deployments(/[^/]+/reconcile)?))?)$"}},{"path":{"type":"RegularExpression","value":"^/orgs/[^/]+/plugins/[^/]+/projects/[^/]+/envs/[^/]+/deployments/[^/]+/(logs|outputs)$"}},{"path":{"type":"RegularExpression","value":"^/(plugin-packages|plugin-installations(/[^/]+(/(identity|upgrade|organization-mode|actions/[^/]+|organizations/[^/]+))?)?|plugin-entitlement-bundles|plugin-audit-events)$"}}]` | Path matching rules for control plane API endpoints |
| control-plane.gatewayApiOidc | object | `{"route":{}}` | Gateway API HTTPRoute for OIDC provider (created when global Gateway API is enabled) |
| control-plane.image | object | `{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-cp","tag":"v3.1.0-rc.2@sha256:88ec47df97767592d310173bcd1f9ce9885ac25deb4f0db009364dd1881d66af"}` | Container image for the control plane |
| control-plane.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| control-plane.image.repository | string | `"ghcr.io/stellwerk-labs/platform-orchestrator-cp"` | Image repository. Prepend repository hostname and path as per your setup, e.g. `my-registry.example.com/orchestrator/platform-orchestrator-cp` |
| control-plane.image.tag | string | `"v3.1.0-rc.2@sha256:88ec47df97767592d310173bcd1f9ce9885ac25deb4f0db009364dd1881d66af"` | Image tag |
| control-plane.nodeSelector | object | `{}` | Node selector constraints |
| control-plane.otel | object | `{"enabled":false,"env":"production"}` | OpenTelemetry configuration |
| control-plane.otel.enabled | bool | `false` | Enable OpenTelemetry instrumentation |
| control-plane.otel.env | string | `"production"` | OTEL environment name (used in resource attributes) |
| control-plane.podAnnotations | object | `{}` | Additional pod annotations |
| control-plane.podLabels | object | `{}` | Additional pod labels |
| control-plane.podSecurityContext | object | `{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context |
| control-plane.replicaCount | int | `1` | Number of replicas |
| control-plane.resources | object | `{}` | CPU/memory resource requests and limits |
| control-plane.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}` | Container-level security context |
| control-plane.service | object | `{"createHeadless":false,"port":8080,"type":"ClusterIP"}` | Service configuration |
| control-plane.service.createHeadless | bool | `false` | Select headless mode for this Service, keeping its name (required for data plane internal communication) |
| control-plane.service.port | int | `8080` | Service port |
| control-plane.service.type | string | `"ClusterIP"` | Service type |
| control-plane.serviceAccount | object | `{"allowCreateToken":true}` | Service account configuration |
| control-plane.serviceAccount.allowCreateToken | bool | `true` | Allow the service account to create tokens (needed for Vault auth) |
| control-plane.serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| control-plane.serviceAccount.create | bool | `true` | Create a dedicated service account |
| control-plane.serviceAccount.name | string | `""` | Override the service account name (defaults to fullname) |
| control-plane.startupProbe | object | `{"failureThreshold":60,"httpGet":{"path":"/alive","port":8080,"scheme":"HTTP"},"periodSeconds":5}` | Startup probe delaying liveness checks until dependencies and database migrations are ready. Adjust the budget for large upgrades; set to null to disable. |
| control-plane.strategy | object | `{}` | Deployment update strategy |
| control-plane.tolerations | list | `[]` | Pod tolerations |
| data-plane | object | `{"config":{"DATABASE_HOST":"platform-orchestrator-cnpg-databases","DATABASE_NAME":"orchestrator-dataplane","DATABASE_PORT":"5432","DEPLOYMENT_QUEUE_DEFAULT_TTL":"2h","DEPLOYMENT_QUEUE_MAX_DEPTH":"10","DEPLOYMENT_QUEUE_MAX_TTL":"24h","INTERNAL_DATAPLANE_HOSTNAME":"platform-orchestrator-data-plane.platform-orchestrator.svc.cluster.local","K8S_RUNNER_POD_SCHEDULING_DELAY":"30s","NATS_URL":"nats://platform-orchestrator-nats:4222","OIDC_ISSUER_URL":"","OTEL_EXPORTER_OTLP_ENDPOINT":"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317","RUNNER_GATEWAY_INTERNAL_URL":"http://platform-orchestrator-runner-gateway.platform-orchestrator.svc:8080/runner-gateway","RUNNER_GATEWAY_URL":"https://api.platform-orchestrator.local/runner-gateway","RUNNER_IMAGE":"ghcr.io/stellwerk-labs/platform-orchestrator-runner:v3.1.0@sha256:6a18787b33aa1c4173982ac5876a62b1cde49307fe1f7a4e86b52f1519134d43","VAULT_AUTH":"kubernetes:platform-orchestrator-data-plane:platform-orchestrator","VAULT_ROLE":"orchestrator-data-plane"},"configurationProfiles":{"deploymentAdmission":{"config":{"DEPLOYMENT_ADMISSION_CORE_BEARER_TOKEN_FILE":"/var/run/secrets/stellwerk/deployment-admission/core-bearer-token","DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL":""},"enabled":false,"httpsOrigins":["DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL"],"requiredConfig":["DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL"],"secretFiles":[{"key":"core-bearer-token","mountPath":"/var/run/secrets/stellwerk/deployment-admission/core-bearer-token","name":"deployment-admission-core-token","secretName":""}]},"nativeExternalDeployment":{"config":{"EXTERNAL_DEPLOYMENT_CORE_BEARER_TOKEN_FILE":"/var/run/secrets/stellwerk/plugins/core-bearer-token","EXTERNAL_DEPLOYMENT_CORE_GATEWAY_URL":"","EXTERNAL_DEPLOYMENT_ENABLED":"true","EXTERNAL_DEPLOYMENT_ISSUER":"stellwerk-control-plane","EXTERNAL_DEPLOYMENT_VERIFICATION_KEY_FILE":"/var/run/secrets/stellwerk/plugins/gateway-public-key.pem"},"enabled":false,"httpsOrigins":["EXTERNAL_DEPLOYMENT_CORE_GATEWAY_URL"],"requiredConfig":["EXTERNAL_DEPLOYMENT_CORE_GATEWAY_URL"],"secretFiles":[{"key":"gateway-public-key.pem","mountPath":"/var/run/secrets/stellwerk/plugins/gateway-public-key.pem","name":"native-plugin-verification-key","secretName":""},{"key":"core-bearer-token","mountPath":"/var/run/secrets/stellwerk/plugins/core-bearer-token","name":"native-plugin-core-token","secretName":""}]}},"env":[{"name":"DATABASE_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"dataplane-db-secret"}}},{"name":"DATABASE_USER","valueFrom":{"secretKeyRef":{"key":"username","name":"dataplane-db-secret"}}},{"name":"NATS_TOKEN","valueFrom":{"secretKeyRef":{"key":"natsAuthToken","name":"platform-orchestrator-secrets"}}},{"name":"RUNNER_TOKEN_SALT","valueFrom":{"secretKeyRef":{"key":"runnerTokenSalt","name":"platform-orchestrator-secrets"}}}],"gatewayApi":{"route":{"matches":[{"path":{"type":"RegularExpression","value":"/orgs/[^/]+/(deployments|deployment-queue|last-deployments|active-resources|metadata-keys)($|/.*)"}}],"timeouts":{"request":"45s"}}},"gatewayApiOidc":{"route":{"matches":[{"path":{"type":"RegularExpression","value":"/\\.well-known/(openid-configuration|jwks)$"}}]}},"image":{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-dp","tag":"v4.0.0-rc.2@sha256:619594c1484a06d229ee861bfdcf8fe36a588aea8bea142095b9fdca1c8a616b"},"service":{"createHeadless":true},"serviceAccount":{"allowCreateToken":true}}` | --------------------------------------------------------------------------- The data plane handles deployments, active resources and logs. It is deployed as a backend-module subchart. |
| data-plane.affinity | object | `{}` | Pod affinity rules |
| data-plane.config | object | `{"DATABASE_HOST":"platform-orchestrator-cnpg-databases","DATABASE_NAME":"orchestrator-dataplane","DATABASE_PORT":"5432","DEPLOYMENT_QUEUE_DEFAULT_TTL":"2h","DEPLOYMENT_QUEUE_MAX_DEPTH":"10","DEPLOYMENT_QUEUE_MAX_TTL":"24h","INTERNAL_DATAPLANE_HOSTNAME":"platform-orchestrator-data-plane.platform-orchestrator.svc.cluster.local","K8S_RUNNER_POD_SCHEDULING_DELAY":"30s","NATS_URL":"nats://platform-orchestrator-nats:4222","OIDC_ISSUER_URL":"","OTEL_EXPORTER_OTLP_ENDPOINT":"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317","RUNNER_GATEWAY_INTERNAL_URL":"http://platform-orchestrator-runner-gateway.platform-orchestrator.svc:8080/runner-gateway","RUNNER_GATEWAY_URL":"https://api.platform-orchestrator.local/runner-gateway","RUNNER_IMAGE":"ghcr.io/stellwerk-labs/platform-orchestrator-runner:v3.1.0@sha256:6a18787b33aa1c4173982ac5876a62b1cde49307fe1f7a4e86b52f1519134d43","VAULT_AUTH":"kubernetes:platform-orchestrator-data-plane:platform-orchestrator","VAULT_ROLE":"orchestrator-data-plane"}` | Configuration environment variables (injected via ConfigMap) |
| data-plane.config.DATABASE_HOST | string | `"platform-orchestrator-cnpg-databases"` | PostgreSQL host (should match the CNPG cluster service name) |
| data-plane.config.DATABASE_NAME | string | `"orchestrator-dataplane"` | PostgreSQL database name for the data plane |
| data-plane.config.DATABASE_PORT | string | `"5432"` | PostgreSQL port |
| data-plane.config.DEPLOYMENT_QUEUE_DEFAULT_TTL | string | `"2h"` | How long a queued deploy or rollback waits before it expires, unless the request sets its own TTL |
| data-plane.config.DEPLOYMENT_QUEUE_MAX_DEPTH | string | `"10"` | Most deploy and rollback requests one Environment may hold in its deployment queue |
| data-plane.config.DEPLOYMENT_QUEUE_MAX_TTL | string | `"24h"` | Longest TTL a queued request may ask for |
| data-plane.config.INTERNAL_DATAPLANE_HOSTNAME | string | `"platform-orchestrator-data-plane.platform-orchestrator.svc.cluster.local"` | Internal data plane hostname (headless service FQDN) Format: <headless svc name>.<namespace>.svc.cluster.local |
| data-plane.config.K8S_RUNNER_POD_SCHEDULING_DELAY | string | `"30s"` | Scheduling delay for runner pods |
| data-plane.config.NATS_URL | string | `"nats://platform-orchestrator-nats:4222"` | NATS endpoint used for durable deployment and runner messages |
| data-plane.config.OIDC_ISSUER_URL | string | `""` | OIDC issuer URL for the built-in OIDC provider (leave empty to disable) |
| data-plane.config.OTEL_EXPORTER_OTLP_ENDPOINT | string | `"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317"` | OpenTelemetry collector endpoint |
| data-plane.config.RUNNER_GATEWAY_INTERNAL_URL | string | `"http://platform-orchestrator-runner-gateway.platform-orchestrator.svc:8080/runner-gateway"` | Namespace-qualified gateway for Kubernetes runner Jobs in any namespace of this cluster. Override for a different release name or Orchestrator namespace. |
| data-plane.config.RUNNER_GATEWAY_URL | string | `"https://api.platform-orchestrator.local/runner-gateway"` | Public HTTPS gateway used by runner Jobs outside this Kubernetes cluster. Keep the hostname aligned with global.gatewayApi.backend.hostname. |
| data-plane.config.RUNNER_IMAGE | string | `"ghcr.io/stellwerk-labs/platform-orchestrator-runner:v3.1.0@sha256:6a18787b33aa1c4173982ac5876a62b1cde49307fe1f7a4e86b52f1519134d43"` | Runner image used for deployments. Prepend repository hostname and path as per your setup, e.g. `my-registry.example.com/orchestrator/platform-orchestrator-runner:vX.Y.Z` |
| data-plane.config.VAULT_AUTH | string | `"kubernetes:platform-orchestrator-data-plane:platform-orchestrator"` | Vault authentication string Format: "kubernetes:<service account name>:<audience1>,<audience2>" |
| data-plane.config.VAULT_ROLE | string | `"orchestrator-data-plane"` | Vault role for the data plane |
| data-plane.configurationProfiles | object | `{"deploymentAdmission":{"config":{"DEPLOYMENT_ADMISSION_CORE_BEARER_TOKEN_FILE":"/var/run/secrets/stellwerk/deployment-admission/core-bearer-token","DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL":""},"enabled":false,"httpsOrigins":["DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL"],"requiredConfig":["DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL"],"secretFiles":[{"key":"core-bearer-token","mountPath":"/var/run/secrets/stellwerk/deployment-admission/core-bearer-token","name":"deployment-admission-core-token","secretName":""}]},"nativeExternalDeployment":{"config":{"EXTERNAL_DEPLOYMENT_CORE_BEARER_TOKEN_FILE":"/var/run/secrets/stellwerk/plugins/core-bearer-token","EXTERNAL_DEPLOYMENT_CORE_GATEWAY_URL":"","EXTERNAL_DEPLOYMENT_ENABLED":"true","EXTERNAL_DEPLOYMENT_ISSUER":"stellwerk-control-plane","EXTERNAL_DEPLOYMENT_VERIFICATION_KEY_FILE":"/var/run/secrets/stellwerk/plugins/gateway-public-key.pem"},"enabled":false,"httpsOrigins":["EXTERNAL_DEPLOYMENT_CORE_GATEWAY_URL"],"requiredConfig":["EXTERNAL_DEPLOYMENT_CORE_GATEWAY_URL"],"secretFiles":[{"key":"gateway-public-key.pem","mountPath":"/var/run/secrets/stellwerk/plugins/gateway-public-key.pem","name":"native-plugin-verification-key","secretName":""},{"key":"core-bearer-token","mountPath":"/var/run/secrets/stellwerk/plugins/core-bearer-token","name":"native-plugin-core-token","secretName":""}]}}` | Optional Data Plane profiles. Each is inert until an operator enables it and supplies its settings and referenced Secrets. The admission endpoints are not public: the operator provides the authenticated HTTPS backend Gateway origin. |
| data-plane.configurationProfiles.deploymentAdmission | object | `{"config":{"DEPLOYMENT_ADMISSION_CORE_BEARER_TOKEN_FILE":"/var/run/secrets/stellwerk/deployment-admission/core-bearer-token","DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL":""},"enabled":false,"httpsOrigins":["DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL"],"requiredConfig":["DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL"],"secretFiles":[{"key":"core-bearer-token","mountPath":"/var/run/secrets/stellwerk/deployment-admission/core-bearer-token","name":"deployment-admission-core-token","secretName":""}]}` | Ordinary Deployment admission: the Data Plane asks Core to guard each ordinary Deployment before it commits it, with the token of its IAM platform principal, the one that `control-plane.configurationProfiles.deploymentAdmission` names. The plugin admission checker can be the same principal and token. Enable together with the Control Plane profile. |
| data-plane.configurationProfiles.nativeExternalDeployment | object | `{"config":{"EXTERNAL_DEPLOYMENT_CORE_BEARER_TOKEN_FILE":"/var/run/secrets/stellwerk/plugins/core-bearer-token","EXTERNAL_DEPLOYMENT_CORE_GATEWAY_URL":"","EXTERNAL_DEPLOYMENT_ENABLED":"true","EXTERNAL_DEPLOYMENT_ISSUER":"stellwerk-control-plane","EXTERNAL_DEPLOYMENT_VERIFICATION_KEY_FILE":"/var/run/secrets/stellwerk/plugins/gateway-public-key.pem"},"enabled":false,"httpsOrigins":["EXTERNAL_DEPLOYMENT_CORE_GATEWAY_URL"],"requiredConfig":["EXTERNAL_DEPLOYMENT_CORE_GATEWAY_URL"],"secretFiles":[{"key":"gateway-public-key.pem","mountPath":"/var/run/secrets/stellwerk/plugins/gateway-public-key.pem","name":"native-plugin-verification-key","secretName":""},{"key":"core-bearer-token","mountPath":"/var/run/secrets/stellwerk/plugins/core-bearer-token","name":"native-plugin-core-token","secretName":""}]}` | Native external-deployment admission for plugin dispatches, with the verifier key and the plugin admission checker's token. |
| data-plane.env | list | `[{"name":"DATABASE_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"dataplane-db-secret"}}},{"name":"DATABASE_USER","valueFrom":{"secretKeyRef":{"key":"username","name":"dataplane-db-secret"}}},{"name":"NATS_TOKEN","valueFrom":{"secretKeyRef":{"key":"natsAuthToken","name":"platform-orchestrator-secrets"}}},{"name":"RUNNER_TOKEN_SALT","valueFrom":{"secretKeyRef":{"key":"runnerTokenSalt","name":"platform-orchestrator-secrets"}}}]` | Additional environment variables (injected directly into the pod spec) Typically used for secret references |
| data-plane.envFromSecrets | list | `[]` | Names of secrets to load as environment variables via envFrom |
| data-plane.gatewayApi | object | `{"route":{"matches":[{"path":{"type":"RegularExpression","value":"/orgs/[^/]+/(deployments|deployment-queue|last-deployments|active-resources|metadata-keys)($|/.*)"}}],"timeouts":{"request":"45s"}}}` | Gateway API HTTPRoute configuration for the data plane |
| data-plane.gatewayApi.route.matches | list | `[{"path":{"type":"RegularExpression","value":"/orgs/[^/]+/(deployments|deployment-queue|last-deployments|active-resources|metadata-keys)($|/.*)"}}]` | Path matching rules for data plane API endpoints |
| data-plane.gatewayApi.route.timeouts | object | `{"request":"45s"}` | Request timeout for data plane routes |
| data-plane.gatewayApiOidc | object | `{"route":{"matches":[{"path":{"type":"RegularExpression","value":"/\\.well-known/(openid-configuration|jwks)$"}}]}}` | Gateway API HTTPRoute for OIDC endpoints (built-in OIDC provider) |
| data-plane.image | object | `{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-dp","tag":"v4.0.0-rc.2@sha256:619594c1484a06d229ee861bfdcf8fe36a588aea8bea142095b9fdca1c8a616b"}` | Container image for the data plane |
| data-plane.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| data-plane.image.repository | string | `"ghcr.io/stellwerk-labs/platform-orchestrator-dp"` | Image repository. Prepend repository hostname and path as per your setup, e.g. `my-registry.example.com/orchestrator/platform-orchestrator-dp` |
| data-plane.image.tag | string | `"v4.0.0-rc.2@sha256:619594c1484a06d229ee861bfdcf8fe36a588aea8bea142095b9fdca1c8a616b"` | Image tag |
| data-plane.nodeSelector | object | `{}` | Node selector constraints |
| data-plane.otel | object | `{"enabled":false,"env":"production"}` | OpenTelemetry configuration |
| data-plane.otel.enabled | bool | `false` | Enable OpenTelemetry instrumentation |
| data-plane.otel.env | string | `"production"` | OTEL environment name (used in resource attributes) |
| data-plane.podAnnotations | object | `{}` | Additional pod annotations |
| data-plane.podLabels | object | `{}` | Additional pod labels |
| data-plane.podSecurityContext | object | `{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context |
| data-plane.replicaCount | int | `1` | Number of replicas |
| data-plane.resources | object | `{}` | CPU/memory resource requests and limits |
| data-plane.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}` | Container-level security context |
| data-plane.service | object | `{"createHeadless":true}` | Service configuration |
| data-plane.service.createHeadless | bool | `true` | Select headless mode for the existing data plane Service (required for internal communication) |
| data-plane.service.port | int | `8080` | Service port |
| data-plane.service.type | string | `"ClusterIP"` | Service type |
| data-plane.serviceAccount | object | `{"allowCreateToken":true}` | Service account configuration |
| data-plane.serviceAccount.allowCreateToken | bool | `true` | Allow the service account to create tokens (needed for Vault auth) |
| data-plane.serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| data-plane.serviceAccount.create | bool | `true` | Create a dedicated service account |
| data-plane.serviceAccount.name | string | `""` | Override the service account name (defaults to fullname) |
| data-plane.startupProbe | object | `{"failureThreshold":60,"httpGet":{"path":"/alive","port":8080,"scheme":"HTTP"},"periodSeconds":5}` | Startup probe delaying liveness checks until dependencies and database migrations are ready. Adjust the budget for large upgrades; set to null to disable. |
| data-plane.strategy | object | `{}` | Deployment update strategy |
| data-plane.tolerations | list | `[]` | Pod tolerations |
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
| global.config | object | `{"CONTROL_PLANE_URL":"http://platform-orchestrator-control-plane:8080","DATA_PLANE_URL":"http://platform-orchestrator-data-plane:8080","IAM_URL":"http://platform-orchestrator-iam:8080","NATS_URL":"nats://platform-orchestrator-nats:4222","VAULT_URL":"http://openbao.openbao:8200"}` | ------------------------------------------------------------------------- These are used for inter-service communication within the cluster. |
| global.config.CONTROL_PLANE_URL | string | `"http://platform-orchestrator-control-plane:8080"` | Internal URL of the control plane service |
| global.config.DATA_PLANE_URL | string | `"http://platform-orchestrator-data-plane:8080"` | Internal URL of the data plane service |
| global.config.IAM_URL | string | `"http://platform-orchestrator-iam:8080"` | Internal URL of the IAM service |
| global.config.NATS_URL | string | `"nats://platform-orchestrator-nats:4222"` | NATS endpoint shared by the control plane, data plane, and IAM service |
| global.config.VAULT_URL | string | `"http://openbao.openbao:8200"` | Vault URL for secret management |
| global.enableAdminApi | bool | `true` | Enable the admin API (generates a superUserToken in the secrets) |
| global.gatewayApi | object | `{"backend":{"cors":{"allowCredentials":true,"allowHeaders":["DNT","Keep-Alive","User-Agent","X-Requested-With","If-Modified-Since","Cache-Control","Content-Type","Range","Authorization","Platform-Orchestrator-User-Agent","Idempotency-Key","If-Match"],"allowMethods":["GET","POST","PUT","PATCH","DELETE","OPTIONS"],"allowOrigins":["https://*.platform-orchestrator.local"],"exposeHeaders":["Etag","Link"],"maxAge":"24h"},"extAuth":{"port":8080,"service":"platform-orchestrator-iam"},"hostname":"api.platform-orchestrator.local","http":true,"https":true,"tls":{"certificateRefs":[{"kind":"Secret","name":"api-platform-orchestrator-cert"}]}},"className":"envoy-gateway","enabled":true,"frontend":{"cors":{"allowCredentials":true,"allowMethods":["GET","POST","PUT","PATCH","DELETE","OPTIONS"],"allowOrigins":["https://*.platform-orchestrator.local"],"maxAge":"24h"},"hostname":"console.platform-orchestrator.local","http":true,"https":true,"tls":{"certificateRefs":[{"kind":"Secret","name":"console-platform-orchestrator-cert"}]}},"keycloak":{"hostname":"keycloak.platform-orchestrator.local","http":true,"https":true,"tls":{"certificateRefs":[{"kind":"Secret","name":"keycloak-platform-orchestrator-cert"}]}},"oidc":{},"useEnvoyGateway":true}` | ------------------------------------------------------------------------- Configures Kubernetes Gateway API resources (Gateways, HTTPRoutes, SecurityPolicies) for external access to the Platform Orchestrator. |
| global.gatewayApi.backend | object | `{"cors":{"allowCredentials":true,"allowHeaders":["DNT","Keep-Alive","User-Agent","X-Requested-With","If-Modified-Since","Cache-Control","Content-Type","Range","Authorization","Platform-Orchestrator-User-Agent","Idempotency-Key","If-Match"],"allowMethods":["GET","POST","PUT","PATCH","DELETE","OPTIONS"],"allowOrigins":["https://*.platform-orchestrator.local"],"exposeHeaders":["Etag","Link"],"maxAge":"24h"},"extAuth":{"port":8080,"service":"platform-orchestrator-iam"},"hostname":"api.platform-orchestrator.local","http":true,"https":true,"tls":{"certificateRefs":[{"kind":"Secret","name":"api-platform-orchestrator-cert"}]}}` | Backend (API) gateway configuration |
| global.gatewayApi.backend.cors | object | `{"allowCredentials":true,"allowHeaders":["DNT","Keep-Alive","User-Agent","X-Requested-With","If-Modified-Since","Cache-Control","Content-Type","Range","Authorization","Platform-Orchestrator-User-Agent","Idempotency-Key","If-Match"],"allowMethods":["GET","POST","PUT","PATCH","DELETE","OPTIONS"],"allowOrigins":["https://*.platform-orchestrator.local"],"exposeHeaders":["Etag","Link"],"maxAge":"24h"}` | CORS configuration for the backend gateway |
| global.gatewayApi.backend.cors.allowCredentials | bool | `true` | Allow credentials (cookies, authorization headers) |
| global.gatewayApi.backend.cors.allowHeaders | list | `["DNT","Keep-Alive","User-Agent","X-Requested-With","If-Modified-Since","Cache-Control","Content-Type","Range","Authorization","Platform-Orchestrator-User-Agent","Idempotency-Key","If-Match"]` | Allowed request headers |
| global.gatewayApi.backend.cors.allowMethods | list | `["GET","POST","PUT","PATCH","DELETE","OPTIONS"]` | Allowed HTTP methods |
| global.gatewayApi.backend.cors.allowOrigins | list | `["https://*.platform-orchestrator.local"]` | Allowed origins. Envoy Gateway turns each `*` into the regex `.*` over the whole origin. No entry may match a `console.gatewayApi.route.pluginUiOrigins` entry: with plugin UIs, list the exact Console origins |
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
| global.legacySpiceDB | object | `{"database":{"host":"platform-orchestrator-cnpg-databases","name":"orchestrator-spicedb","owner":"spicedb_user","passwordSecretKey":"password","passwordSecretName":"spicedb-db-secret","port":"5432"},"preserveDatabase":true}` | ------------------------------------------------------------------------- |
| global.legacySpiceDB.database.host | string | `"platform-orchestrator-cnpg-databases"` | Legacy SpiceDB PostgreSQL host |
| global.legacySpiceDB.database.name | string | `"orchestrator-spicedb"` | Legacy SpiceDB database name |
| global.legacySpiceDB.database.owner | string | `"spicedb_user"` | Legacy SpiceDB database owner |
| global.legacySpiceDB.database.passwordSecretKey | string | `"password"` | Password key in the legacy database secret |
| global.legacySpiceDB.database.passwordSecretName | string | `"spicedb-db-secret"` | Secret holding the legacy database password |
| global.legacySpiceDB.database.port | string | `"5432"` | Legacy SpiceDB PostgreSQL port |
| global.legacySpiceDB.preserveDatabase | bool | `true` | Preserve and manage the former SpiceDB database, owner, and credentials during the Casbin rollback window. Setting this to false leaves kept resources orphaned for explicit cleanup. |
| iam | object | `{"config":{"ALLOWED_GOOGLE_CLIENT_IDS":"","ALLOWED_MICROSOFT_CLIENT_IDS":"","DATABASE_HOST":"platform-orchestrator-cnpg-databases","DATABASE_NAME":"orchestrator-iam","DATABASE_PORT":"5432","KEYCLOAK_INTERNAL_URL":"http://platform-orchestrator-keycloak-service:8080","NATS_URL":"nats://platform-orchestrator-nats:4222","OTEL_EXPORTER_OTLP_ENDPOINT":"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317","PLUGIN_MANAGER_READERS":"","PLUGIN_MANAGER_WRITERS":"","SSO_CALLBACK_URL_PATH":"/auth/sso/callback"},"configurationProfiles":{"pluginWorkloadIdentity":{"config":{"PLUGIN_WORKLOAD_BINDING_WRITERS":"","PLUGIN_WORKLOAD_JWKS_CA_FILE":"/var/run/secrets/kubernetes.io/serviceaccount/ca.crt","PLUGIN_WORKLOAD_JWKS_TOKEN_FILE":"/var/run/secrets/kubernetes.io/serviceaccount/token","PLUGIN_WORKLOAD_JWKS_URL":"https://kubernetes.default.svc/openid/v1/jwks","PLUGIN_WORKLOAD_STATIC_TOKEN_ADAPTER":"","PLUGIN_WORKLOAD_TOKEN_ISSUER":"","PLUGIN_WORKLOAD_TOKEN_TTL":"15m"},"enabled":false,"requiredConfig":["PLUGIN_WORKLOAD_TOKEN_ISSUER"],"serviceAccountIssuerDiscovery":true},"pluginWorkloadStaticJWKS":{"config":{"PLUGIN_WORKLOAD_JWKS_FILE":"/etc/stellwerk/plugin-workload/jwks.json"},"enabled":false,"secretFiles":[{"key":"jwks.json","mountPath":"/etc/stellwerk/plugin-workload/jwks.json","name":"plugin-workload-jwks","secretName":""}]}},"env":[{"name":"DATABASE_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"iam-db-secret"}}},{"name":"DATABASE_USER","valueFrom":{"secretKeyRef":{"key":"username","name":"iam-db-secret"}}},{"name":"NATS_TOKEN","valueFrom":{"secretKeyRef":{"key":"natsAuthToken","name":"platform-orchestrator-secrets"}}},{"name":"KEYCLOAK_CLIENT_SECRET","valueFrom":{"secretKeyRef":{"key":"clientSecret","name":"keycloak-client-secret"}}},{"name":"SSO_STATE_SECRET","valueFrom":{"secretKeyRef":{"key":"ssoStateSecret","name":"platform-orchestrator-secrets"}}},{"name":"SUPER_USER_TOKEN","valueFrom":{"secretKeyRef":{"key":"superUserToken","name":"platform-orchestrator-secrets"}}}],"gatewayApi":{"route":{"admin":{"matches":[{"path":{"type":"PathPrefix","value":"/admin/orgs"}}],"rewrite":{"path":{"replacePrefixMatch":"/internal/orgs","type":"ReplacePrefixMatch"}}},"matches":[{"path":{"type":"RegularExpression","value":"/(auth/register|auth/logout|auth/login|auth/device|auth/plugin-workload-token|auth/sso/.+|(plugin-workload-bindings(/[^/]+)?)|(platform-principals(/[^/]+(/actions/regenerate)?)?)|(users/.+)|(orgs/[^/]+/members)|(orgs/[^/]+/memberships.*)|(orgs/[^/]+/users/[^/]+/memberships.*)|(orgs/[^/]+/service-users.*)|(orgs/[^/]+/invitations.*)|(orgs/[^/]+/roles.*)|(orgs/[^/]+/permissions)|(orgs/[^/]+/plugins/[^/]+/capabilities)|(orgs/[^/]+/projects/[^/]+/users.*)|(orgs/[^/]+/projects/[^/]+/envs/[^/]+/users.*)|current-user|auth/check-permissions|(devicelogins/.+)|(orgs/[^/]+/scim/group-mappings.*)|(scim/v2/orgs/[^/]+($|/.*)))"}}]}},"image":{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-iam","tag":"v2.5.0-rc.3@sha256:29fec2eae6247b957f8c9c6ef66f9cf4254728b7ed0336675559c812687682f6"},"strategy":{"type":"Recreate"}}` | --------------------------------------------------------------------------- The IAM service handles authentication, authorization, SSO, user management, and role-based access control. It is deployed as a backend-module subchart. |
| iam.affinity | object | `{}` | Pod affinity rules |
| iam.config | object | `{"ALLOWED_GOOGLE_CLIENT_IDS":"","ALLOWED_MICROSOFT_CLIENT_IDS":"","DATABASE_HOST":"platform-orchestrator-cnpg-databases","DATABASE_NAME":"orchestrator-iam","DATABASE_PORT":"5432","KEYCLOAK_INTERNAL_URL":"http://platform-orchestrator-keycloak-service:8080","NATS_URL":"nats://platform-orchestrator-nats:4222","OTEL_EXPORTER_OTLP_ENDPOINT":"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317","PLUGIN_MANAGER_READERS":"","PLUGIN_MANAGER_WRITERS":"","SSO_CALLBACK_URL_PATH":"/auth/sso/callback"}` | Configuration environment variables (injected via ConfigMap) |
| iam.config.ALLOWED_GOOGLE_CLIENT_IDS | string | `""` | Comma-separated Google OAuth client IDs for social login (leave empty to disable) |
| iam.config.ALLOWED_MICROSOFT_CLIENT_IDS | string | `""` | Comma-separated Microsoft OAuth client IDs for social login (leave empty to disable) |
| iam.config.DATABASE_HOST | string | `"platform-orchestrator-cnpg-databases"` | PostgreSQL host (should match the CNPG cluster service name) |
| iam.config.DATABASE_NAME | string | `"orchestrator-iam"` | PostgreSQL database name for IAM |
| iam.config.DATABASE_PORT | string | `"5432"` | PostgreSQL port |
| iam.config.KEYCLOAK_INTERNAL_URL | string | `"http://platform-orchestrator-keycloak-service:8080"` | Keycloak internal URL (in-cluster service URL) |
| iam.config.NATS_URL | string | `"nats://platform-orchestrator-nats:4222"` | NATS endpoint used for durable identity events |
| iam.config.OTEL_EXPORTER_OTLP_ENDPOINT | string | `"http://otel-agent-collector.opentelemetry.svc.cluster.local:4317"` | OpenTelemetry collector endpoint |
| iam.config.PLUGIN_MANAGER_READERS | string | `""` | Comma-separated user IDs (UUIDs) holding the platform permission `plugin_manager_read` (read the Plugin Manager API). Writers also read, so list read-only operators here. Only users qualify: a service user, the internal system identity or the nil UUID stops IAM from starting. Empty grants read to nobody beyond the writers. |
| iam.config.PLUGIN_MANAGER_WRITERS | string | `""` | Comma-separated user IDs (UUIDs) holding the platform permission `plugin_manager_write` (manage plugins through the Plugin Manager API), which includes read. Only users qualify, as for the readers. Empty means nobody can manage plugins. |
| iam.config.SSO_CALLBACK_URL_PATH | string | `"/auth/sso/callback"` | SSO callback URL path |
| iam.configurationProfiles | object | `{"pluginWorkloadIdentity":{"config":{"PLUGIN_WORKLOAD_BINDING_WRITERS":"","PLUGIN_WORKLOAD_JWKS_CA_FILE":"/var/run/secrets/kubernetes.io/serviceaccount/ca.crt","PLUGIN_WORKLOAD_JWKS_TOKEN_FILE":"/var/run/secrets/kubernetes.io/serviceaccount/token","PLUGIN_WORKLOAD_JWKS_URL":"https://kubernetes.default.svc/openid/v1/jwks","PLUGIN_WORKLOAD_STATIC_TOKEN_ADAPTER":"","PLUGIN_WORKLOAD_TOKEN_ISSUER":"","PLUGIN_WORKLOAD_TOKEN_TTL":"15m"},"enabled":false,"requiredConfig":["PLUGIN_WORKLOAD_TOKEN_ISSUER"],"serviceAccountIssuerDiscovery":true},"pluginWorkloadStaticJWKS":{"config":{"PLUGIN_WORKLOAD_JWKS_FILE":"/etc/stellwerk/plugin-workload/jwks.json"},"enabled":false,"secretFiles":[{"key":"jwks.json","mountPath":"/etc/stellwerk/plugin-workload/jwks.json","name":"plugin-workload-jwks","secretName":""}]}}` | Plugin workload identity (contract level v1alpha). Both profiles are disabled by default, which keeps the token exchange off and renders no RBAC. |
| iam.configurationProfiles.pluginWorkloadIdentity | object | `{"config":{"PLUGIN_WORKLOAD_BINDING_WRITERS":"","PLUGIN_WORKLOAD_JWKS_CA_FILE":"/var/run/secrets/kubernetes.io/serviceaccount/ca.crt","PLUGIN_WORKLOAD_JWKS_TOKEN_FILE":"/var/run/secrets/kubernetes.io/serviceaccount/token","PLUGIN_WORKLOAD_JWKS_URL":"https://kubernetes.default.svc/openid/v1/jwks","PLUGIN_WORKLOAD_STATIC_TOKEN_ADAPTER":"","PLUGIN_WORKLOAD_TOKEN_ISSUER":"","PLUGIN_WORKLOAD_TOKEN_TTL":"15m"},"enabled":false,"requiredConfig":["PLUGIN_WORKLOAD_TOKEN_ISSUER"],"serviceAccountIssuerDiscovery":true}` | Exchange projected Kubernetes ServiceAccount tokens of plugin workloads for short-lived IAM tokens. Enabling it requires `PLUGIN_WORKLOAD_TOKEN_ISSUER` and an IAM image with the exchange. IAM then reads the in-cluster JWKS with its own ServiceAccount token and cluster CA; `serviceAccountIssuerDiscovery` mounts that token and binds only the read-only ClusterRole `system:service-account-issuer-discovery`. Set it to false when `pluginWorkloadStaticJWKS` supplies the keys. |
| iam.configurationProfiles.pluginWorkloadIdentity.config.PLUGIN_WORKLOAD_BINDING_WRITERS | string | `""` | Comma-separated IAM principal UUIDs holding the platform-level permission `plugin_workload_binding_write` (the installation controller) |
| iam.configurationProfiles.pluginWorkloadIdentity.config.PLUGIN_WORKLOAD_STATIC_TOKEN_ADAPTER | string | `""` | Transitional adapter keeping static tokens of bound service users usable. Empty disables it; the only accepted version is `v1alpha`. |
| iam.configurationProfiles.pluginWorkloadIdentity.config.PLUGIN_WORKLOAD_TOKEN_ISSUER | string | `""` | The cluster's ServiceAccount token issuer (`--service-account-issuer`), for example `https://kubernetes.default.svc.cluster.local` |
| iam.configurationProfiles.pluginWorkloadIdentity.config.PLUGIN_WORKLOAD_TOKEN_TTL | string | `"15m"` | Lifetime of issued plugin workload tokens, 1m to 15m. Never empty: an empty value overrides the IAM default and fails startup. |
| iam.configurationProfiles.pluginWorkloadStaticJWKS | object | `{"config":{"PLUGIN_WORKLOAD_JWKS_FILE":"/etc/stellwerk/plugin-workload/jwks.json"},"enabled":false,"secretFiles":[{"key":"jwks.json","mountPath":"/etc/stellwerk/plugin-workload/jwks.json","name":"plugin-workload-jwks","secretName":""}]}` | Operator-supplied JWKS for clusters where IAM cannot reach the API server. Mounted read-only from a Secret; roll IAM after replacing it. |
| iam.env | list | `[{"name":"DATABASE_PASSWORD","valueFrom":{"secretKeyRef":{"key":"password","name":"iam-db-secret"}}},{"name":"DATABASE_USER","valueFrom":{"secretKeyRef":{"key":"username","name":"iam-db-secret"}}},{"name":"NATS_TOKEN","valueFrom":{"secretKeyRef":{"key":"natsAuthToken","name":"platform-orchestrator-secrets"}}},{"name":"KEYCLOAK_CLIENT_SECRET","valueFrom":{"secretKeyRef":{"key":"clientSecret","name":"keycloak-client-secret"}}},{"name":"SSO_STATE_SECRET","valueFrom":{"secretKeyRef":{"key":"ssoStateSecret","name":"platform-orchestrator-secrets"}}},{"name":"SUPER_USER_TOKEN","valueFrom":{"secretKeyRef":{"key":"superUserToken","name":"platform-orchestrator-secrets"}}}]` | Additional environment variables (injected directly into the pod spec) Typically used for secret references |
| iam.envFromSecrets | list | `[]` | Names of secrets to load as environment variables via envFrom |
| iam.gatewayApi | object | `{"route":{"admin":{"matches":[{"path":{"type":"PathPrefix","value":"/admin/orgs"}}],"rewrite":{"path":{"replacePrefixMatch":"/internal/orgs","type":"ReplacePrefixMatch"}}},"matches":[{"path":{"type":"RegularExpression","value":"/(auth/register|auth/logout|auth/login|auth/device|auth/plugin-workload-token|auth/sso/.+|(plugin-workload-bindings(/[^/]+)?)|(platform-principals(/[^/]+(/actions/regenerate)?)?)|(users/.+)|(orgs/[^/]+/members)|(orgs/[^/]+/memberships.*)|(orgs/[^/]+/users/[^/]+/memberships.*)|(orgs/[^/]+/service-users.*)|(orgs/[^/]+/invitations.*)|(orgs/[^/]+/roles.*)|(orgs/[^/]+/permissions)|(orgs/[^/]+/plugins/[^/]+/capabilities)|(orgs/[^/]+/projects/[^/]+/users.*)|(orgs/[^/]+/projects/[^/]+/envs/[^/]+/users.*)|current-user|auth/check-permissions|(devicelogins/.+)|(orgs/[^/]+/scim/group-mappings.*)|(scim/v2/orgs/[^/]+($|/.*)))"}}]}}` | Gateway API HTTPRoute configuration for IAM |
| iam.gatewayApi.route.admin | object | `{"matches":[{"path":{"type":"PathPrefix","value":"/admin/orgs"}}],"rewrite":{"path":{"replacePrefixMatch":"/internal/orgs","type":"ReplacePrefixMatch"}}}` | Admin API route configuration (rewrites /admin/orgs -> /internal/orgs) |
| iam.gatewayApi.route.matches | list | `[{"path":{"type":"RegularExpression","value":"/(auth/register|auth/logout|auth/login|auth/device|auth/plugin-workload-token|auth/sso/.+|(plugin-workload-bindings(/[^/]+)?)|(platform-principals(/[^/]+(/actions/regenerate)?)?)|(users/.+)|(orgs/[^/]+/members)|(orgs/[^/]+/memberships.*)|(orgs/[^/]+/users/[^/]+/memberships.*)|(orgs/[^/]+/service-users.*)|(orgs/[^/]+/invitations.*)|(orgs/[^/]+/roles.*)|(orgs/[^/]+/permissions)|(orgs/[^/]+/plugins/[^/]+/capabilities)|(orgs/[^/]+/projects/[^/]+/users.*)|(orgs/[^/]+/projects/[^/]+/envs/[^/]+/users.*)|current-user|auth/check-permissions|(devicelogins/.+)|(orgs/[^/]+/scim/group-mappings.*)|(scim/v2/orgs/[^/]+($|/.*)))"}}]` | Path matching rules for IAM API endpoints (auth, users, roles, etc.) |
| iam.gatewayApiOidc | object | `{"route":{}}` | Gateway API HTTPRoute for OIDC provider (created when global Gateway API is enabled) |
| iam.image | object | `{"repository":"ghcr.io/stellwerk-labs/platform-orchestrator-iam","tag":"v2.5.0-rc.3@sha256:29fec2eae6247b957f8c9c6ef66f9cf4254728b7ed0336675559c812687682f6"}` | Container image for IAM |
| iam.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| iam.image.repository | string | `"ghcr.io/stellwerk-labs/platform-orchestrator-iam"` | Image repository. Prepend repository hostname and path as per your setup, e.g. `my-registry.example.com/orchestrator/platform-orchestrator-iam` |
| iam.image.tag | string | `"v2.5.0-rc.3@sha256:29fec2eae6247b957f8c9c6ef66f9cf4254728b7ed0336675559c812687682f6"` | Image tag |
| iam.nodeSelector | object | `{}` | Node selector constraints |
| iam.otel | object | `{"enabled":false,"env":"production"}` | OpenTelemetry configuration |
| iam.otel.enabled | bool | `false` | Enable OpenTelemetry instrumentation |
| iam.otel.env | string | `"production"` | OTEL environment name (used in resource attributes) |
| iam.podAnnotations | object | `{}` | Additional pod annotations |
| iam.podLabels | object | `{}` | Additional pod labels |
| iam.podSecurityContext | object | `{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context |
| iam.replicaCount | int | `1` | Number of replicas |
| iam.resources | object | `{}` | CPU/memory resource requests and limits |
| iam.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}` | Container-level security context |
| iam.service | object | `{"createHeadless":false,"port":8080,"type":"ClusterIP"}` | Service configuration |
| iam.service.createHeadless | bool | `false` | Select headless mode for this Service, keeping its name (required for data plane internal communication) |
| iam.service.port | int | `8080` | Service port |
| iam.service.type | string | `"ClusterIP"` | Service type |
| iam.serviceAccount | object | `{"allowCreateToken":false,"annotations":{},"create":true,"name":""}` | Service account configuration |
| iam.serviceAccount.allowCreateToken | bool | `false` | Allow the service account to create tokens (needed for Vault auth) |
| iam.serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| iam.serviceAccount.create | bool | `true` | Create a dedicated service account |
| iam.serviceAccount.name | string | `""` | Override the service account name (defaults to fullname) |
| iam.startupProbe | object | `{"failureThreshold":60,"httpGet":{"path":"/alive","port":8080,"scheme":"HTTP"},"periodSeconds":5}` | Startup probe delaying liveness checks until dependencies and database migrations are ready. Adjust the budget for large upgrades; set to null to disable. |
| iam.strategy | object | `{"type":"Recreate"}` | Replace all IAM pods before starting the new version. This prevents old SpiceDB and new Casbin binaries from sharing the database during upgrades. |
| iam.tolerations | list | `[]` | Pod tolerations |
| keycloak | object | `{"enabled":true}` | Keycloak subchart (identity provider) |
| keycloak.bootstrapAdmin | object | `{"secretName":"keycloak-bootstrap-admin"}` | Bootstrap admin credentials |
| keycloak.bootstrapAdmin.secretName | string | `"keycloak-bootstrap-admin"` | Secret name containing the initial admin username and password |
| keycloak.enabled | bool | `true` | Enable the in-cluster Keycloak |
| keycloak.hostname | object | `{"admin":"","hostname":""}` | Hostname configuration |
| keycloak.hostname.admin | string | `""` | Admin console hostname (defaults to the public hostname) |
| keycloak.hostname.hostname | string | `""` | Public hostname for Keycloak (auto-derived from gateway config if empty) |
| keycloak.image | object | `{"repository":"quay.io/keycloak/keycloak","tag":"26.0.5"}` | Container image configuration |
| keycloak.image.repository | string | `"quay.io/keycloak/keycloak"` | Image repository |
| keycloak.image.tag | string | `"26.0.5"` | Image tag |
| keycloak.instances | int | `1` | Number of Keycloak instances |
| keycloak.resources | object | `{}` | CPU/memory resource requests and limits |
| messagingBootstrap.enabled | bool | `true` | Provision immutable JetStream streams and the encrypted runner-log object bucket. |
| messagingBootstrap.image | string | `"natsio/nats-box:0.19.5"` |  |
| messagingBootstrap.maxBytes.deadLetters | string | `"536870912"` |  |
| messagingBootstrap.maxBytes.events | string | `"1073741824"` |  |
| messagingBootstrap.maxBytes.runnerBundles | string | `"3221225472"` |  |
| messagingBootstrap.maxBytes.runnerCommands | string | `"536870912"` |  |
| messagingBootstrap.maxBytes.runnerEvents | string | `"1073741824"` |  |
| messagingBootstrap.maxBytes.runnerLogs | string | `"2147483648"` |  |
| messagingBootstrap.replicas | int | `1` |  |
| nats | object | `{"config":{"jetstream":{"enabled":true,"fileStore":{"enabled":true,"pvc":{"enabled":true,"size":"10Gi"}}},"merge":{"authorization":{"token":"<< $NATS_AUTH_TOKEN >>"}}},"container":{"env":{"NATS_AUTH_TOKEN":{"valueFrom":{"secretKeyRef":{"key":"natsAuthToken","name":"platform-orchestrator-secrets"}}}},"resources":{"limits":{"cpu":"1","memory":"1Gi"},"requests":{"cpu":"100m","memory":"256Mi"}}},"enabled":true}` | Official NATS subchart. Disable it when using an external NATS service. |
| runnerGateway | object | `{"enabled":true,"image":{"pullPolicy":"IfNotPresent","repository":"ghcr.io/stellwerk-labs/platform-orchestrator-runner","tag":"v3.1.0@sha256:6a18787b33aa1c4173982ac5876a62b1cde49307fe1f7a4e86b52f1519134d43"},"replicaCount":2,"resources":{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}},"service":{"port":8080}}` | --------------------------------------------------------------------------- The gateway is the only runner-facing component. It translates the public HTTPS protocol into the internal JetStream streams and object stores. |


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
| `NATS_TOKEN` | `platform-orchestrator-secrets` | `natsAuthToken` | NATS authentication token |

### Data Plane (`data-plane.env`)

| Env Var | Default Secret Name | Secret Key | Description |
|---------|---------------------|------------|-------------|
| `DATABASE_USER` | `dataplane-db-secret` | `username` | PostgreSQL username |
| `DATABASE_PASSWORD` | `dataplane-db-secret` | `password` | PostgreSQL password |
| `NATS_TOKEN` | `platform-orchestrator-secrets` | `natsAuthToken` | NATS authentication token |
| `RUNNER_TOKEN_SALT` | `platform-orchestrator-secrets` | `runnerTokenSalt` | Salt for runner authentication tokens |

### IAM (`iam.env`)

| Env Var | Default Secret Name | Secret Key | Description |
|---------|---------------------|------------|-------------|
| `DATABASE_USER` | `iam-db-secret` | `username` | PostgreSQL username |
| `DATABASE_PASSWORD` | `iam-db-secret` | `password` | PostgreSQL password |
| `NATS_TOKEN` | `platform-orchestrator-secrets` | `natsAuthToken` | NATS authentication token |
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
| `keycloak-db-secret` | `username`, `password` | cnpg-databases | Keycloak |
| `keycloak-bootstrap-admin` | `username`, `password` | keycloak | Keycloak |
| `keycloak-client-secret` | `clientSecret` | keycloak | Keycloak, IAM |
| `platform-orchestrator-secrets` | `natsAuthToken`, `runnerTokenSalt`, `runnerGatewayReceiptKey`, `ssoStateSecret`, `superUserToken` | parent chart | Internal messaging, runner gateway, Control Plane, Data Plane, IAM |
