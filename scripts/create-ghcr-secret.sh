#!/bin/bash

set -e

# Configuration
SECRET_NAME="ghcr-secret"
NAMESPACE="platform-orchestrator"

if [[ -z "$GITHUB_USERNAME" || -z "$GITHUB_TOKEN" ]]; then
    echo "Error: GITHUB_USERNAME and GITHUB_TOKEN environment variables must be set." >&2
    echo "GITHUB_TOKEN must be a Personal Access Token with the 'read:packages' scope." >&2
    exit 1
fi

echo "Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Creating imagePullSecrets from GitHub credentials..."
kubectl create secret docker-registry "$SECRET_NAME" \
    --docker-server=ghcr.io \
    --docker-username="$GITHUB_USERNAME" \
    --docker-password="$GITHUB_TOKEN" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "Secret '$SECRET_NAME' created/updated in namespace '$NAMESPACE'"
