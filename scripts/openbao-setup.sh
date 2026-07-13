#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="openbao"
KEYS_FILE="openbao-keys.json"
PLATFORM_NAMESPACE="platform-orchestrator"
DP_SA="platform-orchestrator-data-plane"
CP_SA="platform-orchestrator-control-plane"
AUDIENCE="platform-orchestrator"
LEADER_POD="openbao-0"

# Discover all openbao pods from the statefulset
discover_openbao_pods() {
  kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=openbao,component=server \
    -o jsonpath='{.items[*].metadata.name}'
}

bexec_on() {
  local pod="$1"; shift
  kubectl exec "$pod" -n "$NAMESPACE" -- sh -c "$1"
}

bexec_token_on() {
  local pod="$1"; shift
  kubectl exec "$pod" -n "$NAMESPACE" -- env BAO_TOKEN="$BAO_TOKEN" sh -c "$1"
}

wait_for_pod() {
  local pod="$1"
  echo "Waiting for $pod container to be ready..."
  local i=0
  while [ $i -lt 60 ]; do
    PHASE=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
    CONTAINER_STARTED=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[?(@.name=="openbao")].started}' 2>/dev/null)
    if [ "$PHASE" = "Running" ] && [ "$CONTAINER_STARTED" = "true" ]; then
      echo "$pod container is running"
      return 0
    fi
    sleep 3
    i=$((i + 1))
  done
  echo "ERROR: Timed out waiting for $pod container"
  return 1
}

# Wait for the leader pod first
wait_for_pod "$LEADER_POD"

# Initialize on openbao-0 if needed
if bexec_on "$LEADER_POD" "bao status -format=json 2>/dev/null || true" | jq -e '.initialized == true' >/dev/null 2>&1; then
  echo "OpenBao is already initialized"

  if [ ! -f "$KEYS_FILE" ]; then
    echo "WARNING: OpenBao is initialized but $KEYS_FILE not found. Skipping unseal and configure."
    echo "If openbao is sealed, you must unseal it manually."
    exit 0
  fi
else
  echo "Initializing openbao on $LEADER_POD..."
  kubectl exec "$LEADER_POD" -n "$NAMESPACE" -- bao operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > "$KEYS_FILE"
  echo "OpenBao initialized. Keys saved to $KEYS_FILE"
fi

UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' "$KEYS_FILE")
BAO_TOKEN=$(jq -r '.root_token' "$KEYS_FILE")

unseal_pod() {
  local pod="$1"
  local sealed
  sealed=$(bexec_on "$pod" "bao status -format=json 2>/dev/null || true" | jq -r '.sealed')
  if [ "$sealed" = "true" ]; then
    echo "Unsealing $pod..."
    kubectl exec "$pod" -n "$NAMESPACE" -- bao operator unseal "$UNSEAL_KEY"
    echo "$pod unsealed"
  else
    echo "$pod is already unsealed"
  fi
}

# Unseal the leader first
unseal_pod "$LEADER_POD"

# Wait and unseal remaining pods
OPENBAO_PODS=$(discover_openbao_pods)
for pod in $OPENBAO_PODS; do
  [ "$pod" = "$LEADER_POD" ] && continue
  wait_for_pod "$pod"
  unseal_pod "$pod"
done

# Configure openbao (runs against leader — replicated to followers via Raft)
echo "Configuring openbao..."

if ! bexec_token_on "$LEADER_POD" "bao secrets list -format=json" | jq -e '."secret/"' >/dev/null 2>&1; then
  bexec_token_on "$LEADER_POD" "bao secrets enable -path=secret kv-v2"
  echo "Enabled KV-v2 engine"
else
  echo "KV-v2 engine already enabled"
fi

if ! bexec_token_on "$LEADER_POD" "bao secrets list -format=json" | jq -e '."transit/"' >/dev/null 2>&1; then
  bexec_token_on "$LEADER_POD" "bao secrets enable -path=transit transit"
  echo "Enabled Transit engine"
else
  echo "Transit engine already enabled"
fi

if ! bexec_token_on "$LEADER_POD" "bao auth list -format=json" | jq -e '."kubernetes/"' >/dev/null 2>&1; then
  bexec_token_on "$LEADER_POD" "bao auth enable kubernetes"
  echo "Enabled Kubernetes auth"
else
  echo "Kubernetes auth already enabled"
fi

bexec_token_on "$LEADER_POD" "bao write auth/kubernetes/config \
  kubernetes_host=https://\$KUBERNETES_SERVICE_HOST:\$KUBERNETES_SERVICE_PORT \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
echo "Configured Kubernetes auth"

bexec_token_on "$LEADER_POD" "bao policy write orchestrator-control-plane - <<EOF
path \"secret/*\" {
  capabilities = [\"create\", \"read\", \"update\", \"delete\", \"list\"]
}
EOF"
echo "Created orchestrator-control-plane policy"

bexec_token_on "$LEADER_POD" "bao policy write orchestrator-data-plane - <<EOF
path \"secret/*\" {
  capabilities = [\"read\", \"list\"]
}
EOF"
echo "Created orchestrator-data-plane policy"

bexec_token_on "$LEADER_POD" "bao policy write orchestrator-data-plane-transit - <<EOF
path \"transit/*\" {
  capabilities = [\"create\", \"read\", \"update\", \"delete\", \"list\"]
}
EOF"
echo "Created orchestrator-data-plane-transit policy"

bexec_token_on "$LEADER_POD" "bao write auth/kubernetes/role/orchestrator-control-plane \
  bound_service_account_names=$CP_SA \
  bound_service_account_namespaces=$PLATFORM_NAMESPACE \
  policies=orchestrator-control-plane \
  audience=$AUDIENCE \
  ttl=1h"
echo "Created orchestrator-control-plane role"

bexec_token_on "$LEADER_POD" "bao write auth/kubernetes/role/orchestrator-data-plane \
  bound_service_account_names=$DP_SA \
  bound_service_account_namespaces=$PLATFORM_NAMESPACE \
  policies=orchestrator-data-plane,orchestrator-data-plane-transit \
  audience=$AUDIENCE \
  ttl=1h"
echo "Created orchestrator-data-plane role"

echo "OpenBao setup complete!"
