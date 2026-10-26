# Security maintenance

Unreleased. The application image pins still identify the existing public
releases. Before publishing this chart, replace them with the qualified public
security releases. Private WX1 qualification uses separate image overrides.

The Keycloak server and Operator defaults use 26.8.1, pinned by image digest.
The Operator includes the upstream Keycloak, realm import, OIDC client and SAML
client CRDs. Existing v2alpha1 Keycloak and realm import resources remain served;
the new CRDs also provide v2beta1. The Operator continues to watch all namespaces,
as required when its release and the Orchestrator use different namespaces.
Its default server image now points to the Keycloak server, separately from the
Operator's own image.

GatewayClass chart 0.1.1 adds optional `service.externalTrafficPolicy` for NodePort
and LoadBalancer services. Leaving it empty preserves Envoy Gateway's default.
`Local` preserves client source IPs and needs a ready proxy on every node that
receives external traffic. `Cluster` forwards to ready proxies on other nodes
and can change the source IP seen by the proxy. Choose the policy for the
installation's ingress path and IP-based rules.

A single proxy can move to another node during an upgrade. With `Local`, a
public NodePort on a node without that proxy then drops traffic even when the
Deployment is Ready and xDS reports no errors. Verify the real external HTTP and
TLS paths after a proxy replacement. This behavior predates Envoy Gateway 1.9.

Back up the Keycloak database and configuration before upgrading. Moving from
26.0.x to 26.8.x requires a server stop and database migration. A one-instance
StatefulSet update stops the old Pod before starting the new one. Do not run old
and new servers concurrently against the same database during this migration.

Helm rollback alone cannot reverse the database migration. To return to the old
Keycloak version, stop the server, restore its original database snapshot and
configuration, then restart the old image. Test this recovery before upgrading
a live installation. Application-only rollback instructions do not cover this
database change. See the [Keycloak upgrade guide](https://www.keycloak.org/docs/26.8.1/upgrading/).

Vendored Operator manifests come from
`keycloak/keycloak-k8s-resources` commit
`81948d26747a61e5348f0f3c832d017b36a9cb1c` (release 26.8.1).
`scripts/sync-keycloak-operator.py` verifies the original file hashes before
applying the chart's image, namespace and cross-namespace controller bindings.
Its `--check` mode detects drift without writing files. This source record does
not assert that the upstream commit or images have verified publisher signatures.
