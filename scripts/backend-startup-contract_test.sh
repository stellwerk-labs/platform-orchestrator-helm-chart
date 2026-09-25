#!/bin/sh
set -eu

chart=${1:-charts/platform-orchestrator}
rendered=$(mktemp)
customized=$(mktemp)
trap 'rm -f "$rendered" "$customized"' EXIT

helm template platform-orchestrator "$chart" >"$rendered"
helm template platform-orchestrator "$chart" \
  --set control-plane.startupProbe.failureThreshold=120 \
  --set data-plane.startupProbe=null >"$customized"

python3 - "$rendered" "$customized" <<'PY'
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
print("Backend startup budget, overrides and readiness contract: PASS")
PY
