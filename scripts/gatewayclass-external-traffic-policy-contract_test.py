#!/usr/bin/env python3
"""Exercise the real GatewayClass chart render without a cluster."""

import os
import subprocess
from pathlib import Path


CHART = Path(os.environ.get("GATEWAYCLASS_CHART", "charts/gatewayclass"))


def render(*values):
    command = ["helm", "template", "gatewayclass", str(CHART),
               "--show-only", "templates/envoyproxy.yaml"]
    for value in values:
        command += ["--set", value]
    return subprocess.run(command, text=True, capture_output=True, check=False)


def succeeds(*values):
    result = render(*values)
    assert result.returncode == 0, result.stderr
    return result.stdout


default = succeeds()
assert "type: ClusterIP" in default
assert "externalTrafficPolicy:" not in default

node_default = succeeds("service.type=NodePort")
assert "type: NodePort" in node_default
assert "externalTrafficPolicy:" not in node_default

# Helm coalescing drops a null value, as can an older --reuse-values map.
node_missing = succeeds("service.type=NodePort", "service.externalTrafficPolicy=null")
assert "type: NodePort" in node_missing
assert "externalTrafficPolicy:" not in node_missing

node_cluster = succeeds("service.type=NodePort", "service.externalTrafficPolicy=Cluster",
                        "service.nodePorts.http=80", "service.nodePorts.https=443")
assert "        externalTrafficPolicy: Cluster\n" in node_cluster
assert node_cluster.count("externalTrafficPolicy:") == 1
assert "nodePort: 80\n" in node_cluster
assert "nodePort: 443\n" in node_cluster

node_local = succeeds("service.type=NodePort", "service.externalTrafficPolicy=Local")
assert "        externalTrafficPolicy: Local\n" in node_local

lb_cluster = succeeds("service.type=LoadBalancer", "service.externalTrafficPolicy=Cluster")
assert "type: LoadBalancer" in lb_cluster
assert "        externalTrafficPolicy: Cluster\n" in lb_cluster

for values, message in (
    (("service.type=ClusterIP", "service.externalTrafficPolicy=Cluster"),
     "requires NodePort or LoadBalancer"),
    (("service.type=Invalid",), "service.type must be"),
    (("service.type=NodePort", "service.externalTrafficPolicy=Wrong"),
     "must be empty, Cluster, or Local"),
    (("service.type=NodePort", "service.externalTrafficPolicy=true"),
     "must be empty, Cluster, or Local"),
    (("service.type=NodePort", "service.externalTrafficPolicy=1"),
     "must be empty, Cluster, or Local"),
):
    result = render(*values)
    assert result.returncode != 0, (values, result.stdout)
    assert message in result.stderr, (values, result.stderr)

print("GatewayClass external traffic policy render contract: PASS")
