#!/usr/bin/env bash

set -euo pipefail

ORG_ID="${1:?Usage: create-initial-org.sh <org-id> <api-hostname>}"
API_HOSTNAME="${2:?Usage: create-initial-org.sh <org-id> <api-hostname>}"
API_URL="https://${API_HOSTNAME}"
NAMESPACE="platform-orchestrator"
SECRET_NAME="platform-orchestrator-secrets"

echo "Waiting for platform-orchestrator API to be ready..."
i=0
while [ $i -lt 60 ]; do
  if curl -sk "${API_URL}/alive" >/dev/null 2>&1; then
    echo "API is reachable"
    break
  fi
  sleep 5
  i=$((i + 1))
done
if [ $i -eq 60 ]; then
  echo "ERROR: Timed out waiting for API at ${API_URL}"
  exit 1
fi

SUPERUSER_TOKEN=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.superUserToken}' | base64 --decode)

# Check if org already exists
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer ${SUPERUSER_TOKEN}" \
  "${API_URL}/admin/orgs/${ORG_ID}")

if [ "$HTTP_CODE" = "200" ]; then
  echo "Organization '${ORG_ID}' already exists, skipping creation"
  exit 0
fi

echo "Creating organization '${ORG_ID}'..."
curl -sk -XPOST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SUPERUSER_TOKEN}" \
  -d "{\"id\":\"${ORG_ID}\"}" \
  "${API_URL}/admin/orgs"

echo ""
echo "Organization '${ORG_ID}' created successfully"
