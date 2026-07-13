#!/bin/bash

set -e

# Read self-signed certificates from the cluster
kubectl get secret api-platform-orchestrator-cert -n platform-orchestrator -o jsonpath='{.data.tls\.crt}' | base64 -d > api-ca.crt
kubectl get secret console-platform-orchestrator-cert -n platform-orchestrator -o jsonpath='{.data.tls\.crt}' | base64 -d > console-ca.crt
kubectl get secret keycloak-platform-orchestrator-cert -n platform-orchestrator -o jsonpath='{.data.tls\.crt}' | base64 -d > keycloak-ca.crt

# Add certificates to the Keychain to trust them (needs root password)
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain console-ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain api-ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain keycloak-ca.crt

# Remove cert files
rm -f api-ca.crt console-ca.crt keycloak-ca.crt
