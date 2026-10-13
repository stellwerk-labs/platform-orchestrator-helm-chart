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
    "/orgs/atlas/module-versions/proposed", "/orgs/atlas_2/module-versions/proposed",
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
    "/orgs/atlas/plugins", "/orgs/atlas/plugins/dev.example.optional-addon",
    "/orgs/atlas/plugins/dev.example.optional-addon/invoke",
    "/orgs/atlas/plugins/dev.example.optional-addon/entitlement",
    "/orgs/atlas/plugins/dev.example.optional-addon/inventory",
    "/orgs/atlas/plugins/dev.example.optional-addon/deployment-reads",
    "/orgs/atlas/plugins/dev.example.optional-addon/authorization-checks",
    "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1",
    "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/modules",
    "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/authorize",
    "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/control",
    "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/resource-events",
    "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/events",
    "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/check",
    "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/inventory",
    "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/deployments",
    "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/deployments/dispatch-1/reconcile",
    "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/pins",
    "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/pins/receipts/command-1",
    "/orgs/atlas/plugins/dev.example.optional-addon/projects/project-1/envs/environment-1/deployments/deployment-1/logs",
    "/orgs/atlas/plugins/dev.example.optional-addon/projects/project-1/envs/environment-1/deployments/deployment-1/outputs",
    "/orgs/atlas/deployment-admissions/admission-1",
    "/orgs/atlas/deployment-admissions/admission-1/settle",
    "/orgs/atlas/deployment-admissions/admission-1/seal-absence",
    "/orgs/atlas/projects", "/orgs/atlas/projects/store",
    "/orgs/atlas/projects/store/envs", "/orgs/atlas/projects/store/envs/prod",
    "/orgs/atlas/projects/store/envs/prod/deletion-impact",
    "/orgs/atlas/projects/store/envs/prod/available-resource-types",
    "/orgs/atlas/projects/store/envs/prod/actions/refresh_runner",
    "/orgs/atlas/projects/store/envs/prod/deployments/deployment-1/actions/acknowledge-outcome",
    "/plugin-packages", "/plugin-installations", "/plugin-installations/installation-1",
    "/plugin-installations/installation-1/identity", "/plugin-installations/installation-1/upgrade",
    "/plugin-installations/installation-1/organization-mode",
    "/plugin-installations/installation-1/actions/activate",
    "/plugin-installations/installation-1/organizations/atlas", "/plugin-entitlement-bundles",
    "/plugin-audit-events",
):
    assert matches(cp, path), f"Core route missing: {path}"
    assert not matches(dp, path) and not matches(iam, path), f"ambiguous Core route: {path}"

for path in ("/orgs//module-versions/proposed", "/orgs/atlas/other/module-versions/proposed",
             "/orgs/atlas/module-versions/proposed/extra", "/orgs/atlas/module-versions/proposed/",
             "/orgs/atlas/module-versions/proposed-extra", "/orgs/atlas/module-versions/other",
             "/orgs/atlas/module-versions", "/internal/orgs/atlas/module-versions/proposed",
             "/xorgs/atlas/module-versions/proposed"):
    assert not any(matches(paths, path) for paths in (cp, dp, iam)), f"unexpected proposed-version route: {path}"

for path in ("/orgs/atlas/deployments", "/orgs/atlas/deployments/id/actions/get-logs",
             "/orgs/atlas/deployments/id/encrypted-outputs", "/orgs/atlas/active-resources",
             "/orgs/atlas/last-deployments", "/orgs/atlas/metadata-keys",
             "/orgs/atlas/deployment-queue", "/orgs/atlas/deployment-queue/item-1",
             "/orgs/atlas/deployment-queue/item-1/actions/cancel"):
    assert matches(dp, path) and not matches(cp, path), f"wrong Deployment owner: {path}"

for path in ("/auth/check-permissions", "/orgs/atlas/permissions",
             "/orgs/atlas/plugins/dev.example.optional-addon/capabilities", "/orgs/atlas/projects/store/users",
             "/orgs/atlas/projects/store/envs/prod/users/user-1/memberships",
             "/auth/plugin-workload-token", "/plugin-workload-bindings", "/plugin-workload-bindings/binding-1",
             "/platform-principals", "/platform-principals/principal-1",
             "/platform-principals/principal-1/actions/regenerate"):
    assert matches(iam, path) and not matches(cp, path) and not matches(dp, path), f"wrong IAM owner: {path}"

for path in ("/internal/orgs/atlas/module-version-pins/pin-1/actions/override",
             "/orgs/atlas/rollouts", "/orgs/atlas/plugins/plugin/private-operation",
             "/orgs/atlas/plugins/dev.example.optional-addon/invoke/extra",
             "/orgs/atlas/plugins/dev.example.optional-addon/capabilities",
             "/orgs/atlas/plugins/dev.example.optional-addon/inventory/extra",
             "/orgs/atlas/plugins/dev.example.optional-addon/entitlement/extra",
             "/orgs/atlas/plugins/dev.example.optional-addon/authorization-checks/extra",
             "/orgs/atlas/plugins/dev.example.optional-addon/operations",
             "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/unknown",
             "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/control/activate",
             "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/events/core",
             "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/pins/receipts",
             "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/pins/receipts/request-1/extra",
             "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/deployments/dispatch-1",
             "/orgs/atlas/plugins/dev.example.optional-addon/operations/operation-1/deployments/dispatch-1/reconcile/extra",
             "/orgs/atlas/plugins/dev.example.optional-addon/projects/project-1/envs/environment-1/deployments/deployment-1/keys",
             "/orgs/atlas/plugins/dev.example.optional-addon/projects/project-1/envs/environment-1/external-deployments/deployment-1/outputs",
             "/orgs/atlas/plugins/dev.example.optional-addon/projects/project-1/envs/environment-1/deployments/deployment-1/outputs/extra",
             "/orgs/atlas/deployment-admissions",
             "/orgs/atlas/deployment-admissions/admission-1/unknown",
             "/orgs/atlas/deployment-admissions/admission-1/settle/extra",
             "/orgs/atlas/deployment-admissions/admission-1/seal-absence/extra",
             "/orgs/atlas/projects/store/envs/prod/actions/force-delete",
             "/orgs/atlas/projects/store/envs/prod/deployments",
             "/orgs/atlas/projects/store/envs/prod/deployments/deployment-1",
             "/orgs/atlas/projects/store/envs/prod/deployments/deployment-1/actions/acknowledge",
             "/orgs/atlas/projects/store/envs/prod/deployments/deployment-1/actions/acknowledge-outcome/extra",
             "/orgs/atlas/projects/store/envs/prod/deployments/deployment-1/actions/retry",
             "/orgs/atlas/projects/store/envs/prod/deployments/a/b/actions/acknowledge-outcome",
             "/orgs/atlas/deployments/deployment-1/actions/acknowledge-outcome"):
    assert not matches(cp, path), f"unexpected public Core route: {path}"

for path in ("/orgs/atlas/plugins/dev.example.optional-addon/capabilities/extra",
             "/orgs/atlas/plugins/dev.example.optional-addon/invoke",
             "/auth/plugin-workload-token/extra", "/plugin-workload-bindings/binding-1/extra",
             "/platform-principals/principal-1/extra", "/platform-principals/principal-1/actions/other",
             "/platform-principals/principal-1/actions/regenerate/extra", "/platform-principalsx"):
    assert not matches(iam, path), f"unexpected public IAM route: {path}"

# IAM's /internal/ API (gateway ext-auth, Core authorisation checks, workload
# binding lookups) is cluster-only. Every rendered rule that reaches IAM either
# matches public paths only or is the admin rule mapping /admin/orgs onto
# /internal/orgs; nothing else may rewrite into /internal/.
iam_rules = []
for name, (_, _, document) in routes.items():
    for rule in re.split(r"^    - ", document.split("\n  rules:\n", 1)[-1], flags=re.M)[1:]:
        if not re.search(r"- name: platform-orchestrator-iam$", rule, re.M):
            continue
        rule_paths = [(kind, value.strip().strip("\"'")) for kind, value in
                      re.findall(r"- path:\s*\n\s*type: (\w+)\s*\n\s*value: (.+)", rule)]
        rewrites = re.findall(r"(replacePrefixMatch|replaceFullPath): (\S+)", rule)
        iam_rules.append(bool(rewrites))
        if rewrites or "URLRewrite" in rule:
            assert rule_paths == [("PathPrefix", "/admin/orgs")], (name, rule_paths)
            assert rewrites == [("replacePrefixMatch", "/internal/orgs")], (name, rewrites)
            continue
        for path in ("/internal/authenticate", "/internal/authorize",
                     "/internal/plugin-workload-bindings", "/internal/platform-principals", "/internal/orgs/atlas/members",
                     "/internal/orgs/atlas/module-version-pins/pin-1/actions/override"):
            assert not matches(rule_paths, path), f"IAM internal path exposed by {name}: {path}"
assert set(iam_rules) == {False, True}, iam_rules

acknowledgement = "/orgs/atlas/projects/store/envs/prod/deployments/deployment-1/actions/acknowledge-outcome"
assert not matches(dp, acknowledgement) and not matches(iam, acknowledgement), "outcome acknowledgement belongs to Core only"

for path in ("/.well-known/openid-configuration", "/.well-known/jwks"):
    assert matches(oidc, path), f"missing OIDC route: {path}"
assert not matches(oidc, "/xwell-known/jwks")
assert "name: platform-orchestrator-backend-gateway" in cp_document
assert "replacePrefixMatch: /internal/orgs" in cp_document
print("Core API route ownership and isolation: PASS")
PY
