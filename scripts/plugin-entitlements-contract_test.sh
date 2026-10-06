#!/bin/sh
set -eu

chart=${1:-charts/platform-orchestrator}
rendered=$(mktemp -d)
trap 'rm -f "$rendered/default.yaml" "$rendered/licensed.yaml" "$rendered/missing-secret.log"; rmdir "$rendered"' EXIT

helm template platform-orchestrator "$chart" >"$rendered/default.yaml"
helm template platform-orchestrator "$chart" \
  --set control-plane.configurationProfiles.nativePluginEntitlements.enabled=true \
  --set-string 'control-plane.configurationProfiles.nativePluginEntitlements.secretFiles[0].secretName=licence-trust-v1' \
  --set-string 'control-plane.configurationProfiles.nativePluginEntitlements.secretFiles[0].name=native-plugin-entitlement-trust' \
  --set-string 'control-plane.configurationProfiles.nativePluginEntitlements.secretFiles[0].key=trust.json' \
  --set-string 'control-plane.configurationProfiles.nativePluginEntitlements.secretFiles[0].mountPath=/etc/stellwerk/entitlements/trust.json' \
  --set-string 'control-plane.configurationProfiles.nativePluginEntitlements.secretFiles[1].secretName=licence-bundle-v1' \
  --set-string 'control-plane.configurationProfiles.nativePluginEntitlements.secretFiles[1].name=native-plugin-entitlement-bundle' \
  --set-string 'control-plane.configurationProfiles.nativePluginEntitlements.secretFiles[1].key=bundle.json' \
  --set-string 'control-plane.configurationProfiles.nativePluginEntitlements.secretFiles[1].mountPath=/etc/stellwerk/entitlements/bundle.json' >"$rendered/licensed.yaml"

if helm template platform-orchestrator "$chart" \
  --set control-plane.configurationProfiles.nativePluginEntitlements.enabled=true \
  >"$rendered/missing-secret.log" 2>&1; then
  echo 'An enabled licence profile must require explicit Secret names.' >&2
  exit 1
fi

python3 - "$rendered" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
assert "PLUGIN_ENTITLEMENT_" not in (root / "default.yaml").read_text()
documents = (root / "licensed.yaml").read_text().split("\n---")
selected = [doc for doc in documents if "PLUGIN_ENTITLEMENT_" in doc or "licence-trust-v1" in doc]
assert len(selected) == 2, "Only Core ConfigMap and Deployment may receive licence material"
for doc in selected:
    assert re.search(r"^  name: platform-orchestrator-control-plane(?:-config)?$", doc, re.M)
    assert "PRIVATE KEY" not in doc
config = next(doc for doc in selected if "kind: ConfigMap" in doc)
assert re.search(r'PLUGIN_ENTITLEMENT_MODE: (?:"production"|production)\s*$', config, re.M)
assert "/etc/stellwerk/entitlements/trust.json" in config
assert "/etc/stellwerk/entitlements/bundle.json" in config
deployment = next(doc for doc in selected if "kind: Deployment" in doc)
assert deployment.count("subPath: secret-value") == 2
assert deployment.count("readOnly: true") == 2
assert "secretName: licence-trust-v1" in deployment
assert "secretName: licence-bundle-v1" in deployment
assert "PLUGIN_HOST_ENABLED" not in config, "A licence must not enable a plugin"
assert "secretName is required" in (root / "missing-secret.log").read_text()
print("Plugin entitlement chart contract passed")
PY
