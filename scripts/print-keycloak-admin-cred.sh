#!/bin/bash

set -e

username=$(kubectl get secret keycloak-bootstrap-admin -n platform-orchestrator -o jsonpath='{.data.username}' | base64 --decode)
password=$(kubectl get secret keycloak-bootstrap-admin -n platform-orchestrator -o jsonpath='{.data.password}' | base64 --decode)
printf 'User:     %s\nPassword: %s\n' "$username" "$password"
