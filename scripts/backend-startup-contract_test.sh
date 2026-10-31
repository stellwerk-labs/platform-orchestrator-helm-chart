#!/bin/sh
set -eu

chart=${1:-charts/platform-orchestrator}
rendered=$(mktemp)
customized=$(mktemp)
captured=$(mktemp)
override=$(mktemp)
captured_values=$(mktemp)
override_values=$(mktemp)
trap 'rm -f "$rendered" "$customized" "$captured" "$override" "$captured_values" "$override_values"' EXIT

cat >"$captured_values" <<'YAML'
control-plane:
  strategy: {}
data-plane:
  strategy: {}
YAML
cat >"$override_values" <<'YAML'
data-plane:
  strategy:
    type: RollingUpdate
YAML

helm template platform-orchestrator "$chart" >"$rendered"
helm template platform-orchestrator "$chart" \
  --set control-plane.startupProbe.failureThreshold=120 \
  --set data-plane.startupProbe=null >"$customized"
helm template platform-orchestrator "$chart" -f "$captured_values" >"$captured"
helm template platform-orchestrator "$chart" -f "$override_values" >"$override"

python3 - "$rendered" "$customized" "$captured" "$override" <<'PY'
import re
import sys

def deployment(filename, component):
    with open(filename, encoding="utf-8") as stream:
        docs = stream.read().split("\n---")
    name = "platform-orchestrator-" + component
    return next(doc for doc in docs if re.search(r"^kind: Deployment$", doc, re.M)
                and re.search(r"^  name: " + re.escape(name) + r"$", doc, re.M))

for component in ("control-plane", "data-plane", "iam"):
    doc = deployment(sys.argv[1], component)
    probe = re.search(r"          startupProbe:\n(.*?)          livenessProbe:", doc, re.S)
    assert probe, f"{component}: startup probe missing from rendered Deployment"
    assert "failureThreshold: 60" in probe.group(1)
    assert "periodSeconds: 5" in probe.group(1)
    assert "path: /alive" in probe.group(1) and "port: 8080" in probe.group(1)
    assert "readinessProbe:" in doc and "path: /health" in doc

assert "failureThreshold: 120" in deployment(sys.argv[2], "control-plane")
assert "startupProbe:" not in deployment(sys.argv[2], "data-plane")
assert "failureThreshold: 60" in deployment(sys.argv[2], "iam")

for filename in (sys.argv[1], sys.argv[3]):
    for component in ("control-plane", "data-plane", "iam"):
        doc = deployment(filename, component)
        assert re.search(r"^  strategy:\n    type: Recreate$", doc, re.M), (filename, component)

assert re.search(r"^  strategy:\n    type: RollingUpdate$",
                 deployment(sys.argv[4], "data-plane"), re.M)
assert re.search(r"^  strategy:\n    type: Recreate$",
                 deployment(sys.argv[4], "control-plane"), re.M)
print("Backend startup budget, readiness, Recreate defaults and overrides: PASS")
PY
