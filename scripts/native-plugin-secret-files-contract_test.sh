#!/bin/sh
set -eu

chart=${1:-charts/platform-orchestrator}
defaults=$(mktemp)
enabled=$(mktemp)
incomplete=$(mktemp)
relative=$(mktemp)
insecure=$(mktemp)
missing_origin=$(mktemp)
values=$(mktemp)
trap 'rm -f "$defaults" "$enabled" "$incomplete" "$relative" "$insecure" "$missing_origin" "$values"' EXIT

helm template platform-orchestrator "$chart" >"$defaults"

cat >"$values" <<'YAML'
control-plane:
  configurationProfiles:
    nativePluginGateway:
      enabled: true
      secretFiles:
        - name: native-plugin-installations
          secretName: cp-plugin-installations
          key: installations.json
          mountPath: /var/run/secrets/stellwerk/plugins/installations.json
        - name: native-plugin-signing-key
          secretName: cp-plugin-signing-key
          key: signing-key.pem
          mountPath: /var/run/secrets/stellwerk/plugins/signing-key.pem
        - name: native-plugin-ca
          secretName: cp-plugin-ca
          key: plugin-ca.pem
          mountPath: /var/run/secrets/stellwerk/plugins/plugin-ca.pem
data-plane:
  configurationProfiles:
    nativeExternalDeployment:
      enabled: true
      config:
        EXTERNAL_DEPLOYMENT_CORE_GATEWAY_URL: https://gateway.example.internal
      secretFiles:
        - name: native-plugin-verification-key
          secretName: dp-plugin-verification-key
          key: gateway-public-key.pem
          mountPath: /var/run/secrets/stellwerk/plugins/gateway-public-key.pem
        - name: native-plugin-core-token
          secretName: dp-plugin-core-token
          key: core-bearer-token
          mountPath: /var/run/secrets/stellwerk/plugins/core-bearer-token
YAML

helm template platform-orchestrator "$chart" -f "$values" >"$enabled"

if helm template platform-orchestrator "$chart" \
  --set control-plane.configurationProfiles.nativePluginGateway.enabled=true \
  >"$incomplete" 2>&1; then
  echo "native plugin gateway accepted incomplete Secret references" >&2
  exit 1
fi
grep -q 'configurationProfiles.nativePluginGateway.secretFiles\[native-plugin-installations\].secretName is required' "$incomplete"

if helm template platform-orchestrator "$chart" -f "$values" \
  --set control-plane.configurationProfiles.nativePluginGateway.secretFiles[0].mountPath=relative/installations.json \
  >"$relative" 2>&1; then
  echo "native plugin gateway accepted a relative Secret mount path" >&2
  exit 1
fi
grep -q 'configurationProfiles.nativePluginGateway.secretFiles\[native-plugin-installations\].mountPath must be absolute' "$relative"

if helm template platform-orchestrator "$chart" -f "$values" \
  --set-string data-plane.configurationProfiles.nativeExternalDeployment.config.EXTERNAL_DEPLOYMENT_CORE_GATEWAY_URL=http://platform-orchestrator-control-plane:8080 \
  >"$insecure" 2>&1; then
  echo "native external Deployment accepted an insecure Core callback origin" >&2
  exit 1
fi
grep -q 'configurationProfiles.nativeExternalDeployment.config.EXTERNAL_DEPLOYMENT_CORE_GATEWAY_URL must be an HTTPS origin' "$insecure"

if helm template platform-orchestrator "$chart" \
  --set data-plane.configurationProfiles.nativeExternalDeployment.enabled=true \
  >"$missing_origin" 2>&1; then
  echo "native external Deployment accepted a missing Core callback origin" >&2
  exit 1
fi
grep -q 'configurationProfiles.nativeExternalDeployment.config.EXTERNAL_DEPLOYMENT_CORE_GATEWAY_URL is required' "$missing_origin"

python3 - "$defaults" "$enabled" <<'PY'
import re
import sys


def documents(filename):
    with open(filename, encoding="utf-8") as stream:
        return stream.read().split("\n---")


def resource(filename, kind, name):
    return next(
        document
        for document in documents(filename)
        if re.search(rf"^kind: {re.escape(kind)}$", document, re.M)
        and re.search(rf"^  name: {re.escape(name)}$", document, re.M)
    )


defaults, enabled = sys.argv[1:]
for component in ("control-plane", "data-plane"):
    default_config = resource(defaults, "ConfigMap", f"platform-orchestrator-{component}-config")
    default_deployment = resource(defaults, "Deployment", f"platform-orchestrator-{component}")
    assert "PLUGIN_HOST_ENABLED" not in default_config
    assert "EXTERNAL_DEPLOYMENT_ENABLED" not in default_config
    assert "native-plugin-installations" not in default_deployment
    assert "native-plugin-verification-key" not in default_deployment

cp_config = resource(enabled, "ConfigMap", "platform-orchestrator-control-plane-config")
cp_deployment = resource(enabled, "Deployment", "platform-orchestrator-control-plane")
assert 'PLUGIN_HOST_ENABLED: "true"' in cp_config
assert "PLUGIN_INSTALLATIONS_FILE: /var/run/secrets/stellwerk/plugins/installations.json" in cp_config
assert "PLUGIN_SIGNING_KEY_FILE: /var/run/secrets/stellwerk/plugins/signing-key.pem" in cp_config
assert "PLUGIN_CA_FILE: /var/run/secrets/stellwerk/plugins/plugin-ca.pem" in cp_config
assert 'PLUGIN_DATA_PLANE_INTERNAL_HTTP: "false"' in cp_config
assert "secretName: cp-plugin-installations" in cp_deployment
assert "secretName: cp-plugin-signing-key" in cp_deployment
assert "secretName: cp-plugin-ca" in cp_deployment
assert 'mountPath: "/var/run/secrets/stellwerk/plugins/installations.json"' in cp_deployment
assert 'mountPath: "/var/run/secrets/stellwerk/plugins/signing-key.pem"' in cp_deployment
assert 'mountPath: "/var/run/secrets/stellwerk/plugins/plugin-ca.pem"' in cp_deployment

dp_config = resource(enabled, "ConfigMap", "platform-orchestrator-data-plane-config")
dp_deployment = resource(enabled, "Deployment", "platform-orchestrator-data-plane")
assert 'EXTERNAL_DEPLOYMENT_ENABLED: "true"' in dp_config
assert "EXTERNAL_DEPLOYMENT_CORE_GATEWAY_URL: https://gateway.example.internal" in dp_config
assert "secretName: dp-plugin-verification-key" in dp_deployment
assert "secretName: dp-plugin-core-token" in dp_deployment
assert 'mountPath: "/var/run/secrets/stellwerk/plugins/gateway-public-key.pem"' in dp_deployment
assert 'mountPath: "/var/run/secrets/stellwerk/plugins/core-bearer-token"' in dp_deployment

iam_config = resource(enabled, "ConfigMap", "platform-orchestrator-iam-config")
iam_deployment = resource(enabled, "Deployment", "platform-orchestrator-iam")
assert "PLUGIN_HOST_ENABLED" not in iam_config
assert "EXTERNAL_DEPLOYMENT_ENABLED" not in iam_config
assert "native-plugin-" not in iam_deployment

print("Native plugin Secret files, disabled defaults, and CP/DP isolation: PASS")
PY
