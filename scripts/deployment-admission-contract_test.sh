#!/bin/sh
set -eu

# Ordinary Deployment admission: Core names one Data Plane identity for every
# organization (a plain UUID, no Secret), and the Data Plane mounts that
# identity's token. Both profiles are off by default and fail closed when
# incomplete.

chart=${1:-charts/platform-orchestrator}
identity=0199a0c1-1d6e-72f2-8000-00000000000a
defaults=$(mktemp)
enabled=$(mktemp)
values=$(mktemp)
refused=$(mktemp)
trap 'rm -f "$defaults" "$enabled" "$values" "$refused"' EXIT

helm template platform-orchestrator "$chart" >"$defaults"

cat >"$values" <<YAML
control-plane:
  configurationProfiles:
    deploymentAdmission:
      enabled: true
      config:
        DEPLOYMENT_ADMISSION_IDENTITY: "$identity"
data-plane:
  configurationProfiles:
    deploymentAdmission:
      enabled: true
      config:
        DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL: https://gateway.example.internal
      secretFiles:
        - name: deployment-admission-core-token
          secretName: dp-admission-token-v1
          key: core-bearer-token
          mountPath: /var/run/secrets/stellwerk/deployment-admission/core-bearer-token
YAML

helm template platform-orchestrator "$chart" -f "$values" >"$enabled"

# refuse MESSAGE ARGS... requires helm template to fail with MESSAGE.
refuse() {
  message=$1
  shift
  if helm template platform-orchestrator "$chart" "$@" >"$refused" 2>&1; then
    echo "deployment admission rendered without: $message" >&2
    exit 1
  fi
  grep -qF "$message" "$refused" || { cat "$refused" >&2; exit 1; }
}

refuse 'configurationProfiles.deploymentAdmission.config.DEPLOYMENT_ADMISSION_IDENTITY is required' \
  --set control-plane.configurationProfiles.deploymentAdmission.enabled=true
refuse 'configurationProfiles.deploymentAdmission.config.DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL is required' \
  --set data-plane.configurationProfiles.deploymentAdmission.enabled=true
refuse 'configurationProfiles.deploymentAdmission.config.DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL must be an HTTPS origin' \
  -f "$values" --set-string data-plane.configurationProfiles.deploymentAdmission.config.DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL=http://platform-orchestrator-control-plane:8080
refuse 'configurationProfiles.deploymentAdmission.secretFiles[deployment-admission-core-token].secretName is required' \
  --set data-plane.configurationProfiles.deploymentAdmission.enabled=true \
  --set-string data-plane.configurationProfiles.deploymentAdmission.config.DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL=https://gateway.example.internal

python3 - "$defaults" "$enabled" "$identity" "$chart/values.yaml" <<'PY'
import re
import sys


def resource(filename, kind, name):
    with open(filename, encoding="utf-8") as stream:
        documents = stream.read().split("\n---")
    return next(
        document
        for document in documents
        if re.search(rf"^kind: {re.escape(kind)}$", document, re.M)
        and re.search(rf"^  name: {re.escape(name)}$", document, re.M)
    )


def admission_config(config):
    return {key: value.strip('"')
            for key, value in re.findall(r"^  (DEPLOYMENT_ADMISSION_[A-Z_]+): (.*)$", config, re.M)}


defaults, enabled, identity, chart_values = sys.argv[1:]

# Helm replaces lists, so operators copy the default Secret entry: its mount
# must be the file the Data Plane reads.
with open(chart_values, encoding="utf-8") as stream:
    data_plane = stream.read().split("\ndata-plane:\n", 1)[1].split("\niam:\n", 1)[0]
profile = re.search(r"^    deploymentAdmission:\n((?:(?: {6}.*)?\n)+)", data_plane, re.M).group(1)
token_file = re.search(r"^        DEPLOYMENT_ADMISSION_CORE_BEARER_TOKEN_FILE: (\S+)$", profile, re.M).group(1)
assert re.findall(r"^          mountPath: (\S+)$", profile, re.M) == [token_file], profile

for component in ("control-plane", "data-plane", "iam"):
    config = resource(defaults, "ConfigMap", f"platform-orchestrator-{component}-config")
    deployment = resource(defaults, "Deployment", f"platform-orchestrator-{component}")
    assert admission_config(config) == {}, (component, admission_config(config))
    assert "deployment-admission" not in deployment, component

# Core: one identity for every organization, nothing mounted, no map.
cp_config = resource(enabled, "ConfigMap", "platform-orchestrator-control-plane-config")
cp_deployment = resource(enabled, "Deployment", "platform-orchestrator-control-plane")
assert admission_config(cp_config) == {"DEPLOYMENT_ADMISSION_IDENTITY": identity}, admission_config(cp_config)
assert "deployment-admission" not in cp_deployment
assert "DEPLOYMENT_ADMISSION_IDENTITIES_FILE" not in open(enabled, encoding="utf-8").read()

# Data Plane: the gateway origin and the identity's token.
dp_config = resource(enabled, "ConfigMap", "platform-orchestrator-data-plane-config")
dp_deployment = resource(enabled, "Deployment", "platform-orchestrator-data-plane")
assert admission_config(dp_config) == {
    "DEPLOYMENT_ADMISSION_CORE_GATEWAY_URL": "https://gateway.example.internal",
    "DEPLOYMENT_ADMISSION_CORE_BEARER_TOKEN_FILE": "/var/run/secrets/stellwerk/deployment-admission/core-bearer-token",
}, admission_config(dp_config)
assert "secretName: dp-admission-token-v1" in dp_deployment
assert 'mountPath: "/var/run/secrets/stellwerk/deployment-admission/core-bearer-token"' in dp_deployment

iam_config = resource(enabled, "ConfigMap", "platform-orchestrator-iam-config")
assert admission_config(iam_config) == {}, admission_config(iam_config)

print("Deployment admission: disabled defaults, one Core identity, Data Plane token mount, refusals: PASS")
PY
