#!/bin/sh
set -eu

# The v1alpha plugin workload token exchange is inert by default. Enabled, it
# adds exactly the IAM configuration keys, a ServiceAccount token mount and one
# binding to the read-only issuer discovery ClusterRole. The unauthenticated
# exchange path is a single exact route on the ext-auth protected IAM route.

chart=${1:-charts/platform-orchestrator}
namespace=plugin-workload-contract
issuer=https://kubernetes.default.svc.cluster.local
writer=0199a0c1-1d6e-72f1-8000-000000000001
defaults=$(mktemp)
enabled=$(mktemp)
static=$(mktemp)
opted_out=$(mktemp)
missing_issuer=$(mktemp)
missing_jwks=$(mktemp)
static_values=$(mktemp)
trap 'rm -f "$defaults" "$enabled" "$static" "$opted_out" "$missing_issuer" "$missing_jwks" "$static_values"' EXIT

render() {
  helm template platform-orchestrator "$chart" --namespace "$namespace" "$@"
}

render >"$defaults"
render \
  --set iam.configurationProfiles.pluginWorkloadIdentity.enabled=true \
  --set-string iam.configurationProfiles.pluginWorkloadIdentity.config.PLUGIN_WORKLOAD_TOKEN_ISSUER="$issuer" \
  --set-string iam.configurationProfiles.pluginWorkloadIdentity.config.PLUGIN_WORKLOAD_BINDING_WRITERS="$writer" \
  >"$enabled"
cat >"$static_values" <<YAML
iam:
  configurationProfiles:
    pluginWorkloadIdentity:
      enabled: true
      serviceAccountIssuerDiscovery: false
      config:
        PLUGIN_WORKLOAD_TOKEN_ISSUER: $issuer
    pluginWorkloadStaticJWKS:
      enabled: true
      secretFiles:
        - name: plugin-workload-jwks
          secretName: iam-plugin-workload-jwks
          key: jwks.json
          mountPath: /etc/stellwerk/plugin-workload/jwks.json
YAML
render -f "$static_values" >"$static"
render \
  --set iam.configurationProfiles.pluginWorkloadIdentity.enabled=true \
  --set iam.configurationProfiles.pluginWorkloadIdentity.serviceAccountIssuerDiscovery=false \
  --set-string iam.configurationProfiles.pluginWorkloadIdentity.config.PLUGIN_WORKLOAD_TOKEN_ISSUER="$issuer" \
  >"$opted_out"

if render --set iam.configurationProfiles.pluginWorkloadIdentity.enabled=true >"$missing_issuer" 2>&1; then
  echo "the plugin workload exchange rendered without an issuer" >&2
  exit 1
fi
grep -q 'configurationProfiles.pluginWorkloadIdentity.config.PLUGIN_WORKLOAD_TOKEN_ISSUER is required' "$missing_issuer"

if render --set iam.configurationProfiles.pluginWorkloadStaticJWKS.enabled=true >"$missing_jwks" 2>&1; then
  echo "the static plugin workload JWKS rendered without a Secret" >&2
  exit 1
fi
grep -q 'configurationProfiles.pluginWorkloadStaticJWKS.secretFiles\[plugin-workload-jwks\].secretName is required' "$missing_jwks"

python3 - "$defaults" "$enabled" "$static" "$opted_out" "$namespace" "$issuer" "$writer" <<'PY'
import re
import sys

defaults_file, enabled_file, static_file, opted_out_file, namespace, issuer, writer = sys.argv[1:]


def documents(filename):
    with open(filename, encoding="utf-8") as handle:
        return [doc for doc in handle.read().split("\n---\n") if doc.strip()]


def kind(doc):
    match = re.search(r"^kind: (\S+)$", doc, re.MULTILINE)
    return match.group(1) if match else ""


def name(doc):
    match = re.search(r"^metadata:\n(?:  .*\n)*?  name: (\S+)$", doc, re.MULTILINE)
    return match.group(1) if match else ""


def find(docs, wanted_kind, wanted_name):
    found = [doc for doc in docs if kind(doc) == wanted_kind and name(doc) == wanted_name]
    assert len(found) == 1, f"expected one {wanted_kind}/{wanted_name}, found {len(found)}"
    return found[0]


def workload_config(docs):
    config = find(docs, "ConfigMap", "platform-orchestrator-iam-config")
    return dict(re.findall(r"^  (PLUGIN_WORKLOAD_[A-Z_]+): (.*)$", config, re.MULTILINE))


def rbac(docs):
    return [doc for doc in docs if kind(doc) in {"Role", "RoleBinding", "ClusterRole", "ClusterRoleBinding"}
            and "platform-orchestrator-iam" in name(doc)]


def automount(docs):
    deployment = find(docs, "Deployment", "platform-orchestrator-iam")
    return re.findall(r"^      automountServiceAccountToken: (\S+)$", deployment, re.MULTILINE)


defaults = documents(defaults_file)
enabled = documents(enabled_file)
static = documents(static_file)
opted_out = documents(opted_out_file)

# Off by default: no keys, no token mount change, no RBAC for IAM.
assert workload_config(defaults) == {}, workload_config(defaults)
assert automount(defaults) == [], "IAM must keep the default token mount behaviour"
assert rbac(defaults) == [], [name(doc) for doc in rbac(defaults)]

# Enabled: exactly the documented keys, an explicit token mount and one binding.
assert workload_config(enabled) == {
    "PLUGIN_WORKLOAD_TOKEN_ISSUER": issuer,
    "PLUGIN_WORKLOAD_JWKS_URL": "https://kubernetes.default.svc/openid/v1/jwks",
    "PLUGIN_WORKLOAD_JWKS_CA_FILE": "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt",
    "PLUGIN_WORKLOAD_JWKS_TOKEN_FILE": "/var/run/secrets/kubernetes.io/serviceaccount/token",
    "PLUGIN_WORKLOAD_TOKEN_TTL": "15m",
    "PLUGIN_WORKLOAD_BINDING_WRITERS": writer,
    "PLUGIN_WORKLOAD_STATIC_TOKEN_ADAPTER": '""',
}, workload_config(enabled)
assert automount(enabled) == ["true"]
bindings = rbac(enabled)
assert [(kind(doc), name(doc)) for doc in bindings] == [
    ("ClusterRoleBinding", "platform-orchestrator-iam-service-account-issuer-discovery")
], [(kind(doc), name(doc)) for doc in bindings]
binding = bindings[0]
assert re.search(r"^roleRef:\n  apiGroup: rbac.authorization.k8s.io\n  kind: ClusterRole\n  name: system:service-account-issuer-discovery$",
                 binding, re.MULTILINE), binding
subjects = binding.split("subjects:\n", 1)[1]
assert subjects.strip() == (
    "- kind: ServiceAccount\n    name: platform-orchestrator-iam\n    namespace: " + namespace
), subjects
assert not any(kind(doc) in {"ClusterRole", "Role"} and "issuer-discovery" in doc for doc in enabled), \
    "the chart must reuse the built-in ClusterRole, not define its own"

# Static JWKS: mounted from the Secret, no discovery binding when opted out.
assert workload_config(static)["PLUGIN_WORKLOAD_JWKS_FILE"] == "/etc/stellwerk/plugin-workload/jwks.json"
static_deployment = find(static, "Deployment", "platform-orchestrator-iam")
assert "secretName: iam-plugin-workload-jwks" in static_deployment
assert 'mountPath: "/etc/stellwerk/plugin-workload/jwks.json"' in static_deployment
assert rbac(static) == [] and automount(static) == []
assert rbac(opted_out) == [] and automount(opted_out) == []

# Routes: the exchange is one exact alternative on the IAM route, bindings are
# authenticated IAM paths, and no other route exposes either.
for docs in (defaults, enabled):
    routes = [doc for doc in docs if kind(doc) == "HTTPRoute"]
    iam_routes = [doc for doc in routes if name(doc) == "platform-orchestrator-iam"]
    assert len(iam_routes) == 1, [name(doc) for doc in routes]
    patterns = re.findall(r'value: "?(/\(auth/register[^"\n]*)', iam_routes[0])
    assert len(patterns) == 1, patterns
    iam_path = re.compile(patterns[0])
    for path in ["/auth/plugin-workload-token", "/plugin-workload-bindings",
                 "/plugin-workload-bindings/0199a0c1-1d6e-72f1-8000-000000000002",
                 "/platform-principals", "/platform-principals/0199a0c1-1d6e-72f1-8000-000000000003",
                 "/platform-principals/0199a0c1-1d6e-72f1-8000-000000000003/actions/regenerate"]:
        assert iam_path.fullmatch(path), path
    for path in ["/auth/plugin-workload-token/extra", "/auth/plugin-workload-tokens",
                 "/auth/plugin-workload-token-other", "/plugin-workload-bindings/a/b",
                 "/plugin-workload-bindingsx"]:
        assert not iam_path.fullmatch(path), path
    for route in routes:
        if route is not iam_routes[0]:
            assert "plugin-workload" not in route, name(route)

print("plugin workload identity contract holds")
PY
