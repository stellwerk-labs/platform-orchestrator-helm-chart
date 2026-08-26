#!/bin/sh
set -eu

chart=${1:-charts/platform-orchestrator}
rendered=$(mktemp)
trap 'rm -f "$rendered"' EXIT

helm template platform-orchestrator "$chart" >"$rendered"

# The public IAM route must expose the SCIM 2.0 endpoints so external IDPs
# (Entra, Okta, Authentik, ...) can provision and deprovision org users.
grep -Fq '(scim/v2/orgs/[^/]+($|/.*))' "$rendered"

# SCIM must stay on the IAM HTTPRoute (behind the gateway's ext-auth), never
# on an unauthenticated route family.
grep -B 40 'scim/v2' "$rendered" | grep -q 'platform-orchestrator-iam'
