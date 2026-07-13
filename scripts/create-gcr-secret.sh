#!/bin/bash

set -e

# Configuration
GOOGLE_APPLICATION_CREDENTIALS="test-credentials.json"
SECRET_NAME="gcr-json-key"
NAMESPACE="platform-orchestrator"

echo "Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Creating imagePullSecrets from credentials file..."
kubectl create secret docker-registry "$SECRET_NAME" \
    --docker-server=europe-docker.pkg.dev \
    --docker-username=_json_key \
    --docker-password="$(cat "$GOOGLE_APPLICATION_CREDENTIALS")" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "Secret '$SECRET_NAME' created/updated in namespace '$NAMESPACE'"
