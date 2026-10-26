# keycloak-operator

Keycloak Operator

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| image.repository | string | `"quay.io/keycloak/keycloak-operator"` |  |
| image.tag | string | `"26.8.1@sha256:2f80ad73eaddbf2420e0b235cfe72ec568d053823f1ef4e3ff80b73d0984a0bc"` |  |
| keycloakImage.repository | string | `"quay.io/keycloak/keycloak"` |  |
| keycloakImage.tag | string | `"26.8.1@sha256:79c623a22abacf3fe6c00a5fb30f5b7843d717b234033b80995891c06116d244"` |  |

## Upgrading

The Operator and default server images are pinned separately. Existing Keycloak
resources can keep their explicit server image while the Operator is upgraded.
The chart watches all namespaces and binds its controllers to the ServiceAccount
in the release namespace.

Back up and rehearse restoration of the Keycloak database before changing the
server version. See the [security maintenance guide](../../docs/security-maintenance.md).
