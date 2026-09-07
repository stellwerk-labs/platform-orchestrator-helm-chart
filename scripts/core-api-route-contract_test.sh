#!/bin/sh
set -eu

chart=${1:-charts/platform-orchestrator}
rendered=$(mktemp)
trap 'rm -f "$rendered"' EXIT

helm template platform-orchestrator "$chart" \
  --set-string global.gatewayApi.oidc.hostname=oidc.example.test >"$rendered"

# Inspect the rendered routes, not the input values: a wrongly nested value
# otherwise looks correct in source while producing no HTTPRoute at all.
python3 - "$rendered" <<'PY'
import re
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    documents = stream.read().split("\n---")

routes = {}
for document in documents:
    if not re.search(r"^kind: HTTPRoute$", document, re.M):
        continue
    name = re.search(r"^  name: (\S+)$", document, re.M).group(1)
    backends = re.findall(r"backendRefs:\s*\n\s*- name: (\S+)", document)
    paths = []
    for kind, value in re.findall(r"- path:\s*\n\s*type: (\w+)\s*\n\s*value: (.+)", document):
        paths.append((kind, value.strip().strip("\"'")))
    routes[name] = (backends, paths, document)

def route(service):
    name = "platform-orchestrator-" + service
    assert name in routes, f"missing rendered HTTPRoute: {name}"
    backends, paths, document = routes[name]
    assert backends and all(backend == name.removesuffix("-oidc") for backend in backends), (name, backends)
    return paths, document

cp, cp_document = route("control-plane")
dp, _ = route("data-plane")
iam, _ = route("iam")
oidc, _ = route("data-plane-oidc")

def matches(paths, path):
    return any((re.fullmatch(pattern, path) is not None if kind == "RegularExpression"
                else path == pattern if kind == "Exact"
                else path == pattern or path.startswith(pattern.rstrip("/") + "/"))
               for kind, pattern in paths)

for path in (
    "/orgs", "/orgs/atlas", "/orgs/atlas/envs",
    "/orgs/atlas/module-catalogue", "/orgs/atlas/modules/redis/catalogue",
    "/orgs/atlas/modules/redis/versions/1.0.0",
    "/orgs/atlas/modules/redis/versions/1.0.0/compare/1.1.0",
    "/orgs/atlas/modules/redis/versions/1.1.0/actions/promote",
    "/orgs/atlas/modules/redis/versions/1.1.0/events",
    "/orgs/atlas/modules/redis/versions/1.1.0/usage",
    "/orgs/atlas/module-version-lifecycle-transactions",
    "/orgs/atlas/module-version-pins/bulk-preview",
    "/orgs/atlas/module-version-pins/bulk",
    "/orgs/atlas/module-version-pins/pin-1/notes",
    "/orgs/atlas/module-version-pins/pin-1/actions/unpin",
    "/orgs/atlas/plugins/dev.example.optional-addon",
    "/orgs/atlas/projects", "/orgs/atlas/projects/store",
    "/orgs/atlas/projects/store/envs", "/orgs/atlas/projects/store/envs/prod",
    "/orgs/atlas/projects/store/envs/prod/deletion-impact",
    "/orgs/atlas/projects/store/envs/prod/available-resource-types",
    "/orgs/atlas/projects/store/envs/prod/actions/refresh_runner",
):
    assert matches(cp, path), f"Core route missing: {path}"
    assert not matches(dp, path) and not matches(iam, path), f"ambiguous Core route: {path}"

for path in ("/orgs/atlas/deployments", "/orgs/atlas/deployments/id/actions/get-logs",
             "/orgs/atlas/deployments/id/encrypted-outputs", "/orgs/atlas/active-resources",
             "/orgs/atlas/last-deployments", "/orgs/atlas/metadata-keys"):
    assert matches(dp, path) and not matches(cp, path), f"wrong Deployment owner: {path}"

for path in ("/auth/check-permissions", "/orgs/atlas/permissions", "/orgs/atlas/projects/store/users",
             "/orgs/atlas/projects/store/envs/prod/users/user-1/memberships"):
    assert matches(iam, path) and not matches(cp, path), f"wrong IAM owner: {path}"

for path in ("/internal/orgs/atlas/module-version-pins/pin-1/actions/override",
             "/orgs/atlas/rollouts", "/orgs/atlas/plugins/plugin/private-operation",
             "/orgs/atlas/projects/store/envs/prod/actions/force-delete"):
    assert not matches(cp, path), f"unexpected public Core route: {path}"

for path in ("/.well-known/openid-configuration", "/.well-known/jwks"):
    assert matches(oidc, path), f"missing OIDC route: {path}"
assert not matches(oidc, "/xwell-known/jwks")
assert "name: platform-orchestrator-backend-gateway" in cp_document
assert "replacePrefixMatch: /internal/orgs" in cp_document
print("Core API route ownership and isolation: PASS")
PY
