#!/usr/bin/env python3
"""Exercise the real Helm-rendered Console CSP and fail-closed plugin UI origin validation."""
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


CHART = Path(__file__).resolve().parents[1] / "charts/platform-orchestrator"
STOCK_CSP = (
    "script-src 'self' 'unsafe-inline' 'unsafe-eval' accounts.google.com "
    "https://hcaptcha.com https://*.hcaptcha.com https://*.wistia.com https://*.wistia.net; "
    "frame-src accounts.google.com https://hcaptcha.com https://*.hcaptcha.com; worker-src blob:;"
)


def render(origins=None, *, gateway_enabled=True, backend=None):
    gateway = {"enabled": gateway_enabled, "frontend": {"hostname": "console.example.test"}}
    if backend is not None:
        gateway["backend"] = backend
    values = {"global": {"gatewayApi": gateway}}
    if origins is not None:
        values["console"] = {"gatewayApi": {"route": {"pluginUiOrigins": origins}}}
    with tempfile.TemporaryDirectory(prefix="console-plugin-csp-") as directory:
        value_file = Path(directory) / "values.json"
        value_file.write_text(json.dumps(values), encoding="utf-8")
        return subprocess.run(
            ["helm", "template", "platform-orchestrator", str(CHART), "-f", str(value_file)],
            text=True, capture_output=True, timeout=30, check=False,
        )


def resource(manifest, kind, name):
    return next(
        document for document in manifest.split("\n---")
        if f"kind: {kind}\n" in document and f"\n  name: {name}\n" in document
    )


def console_csp(manifest):
    route = resource(manifest, "HTTPRoute", "platform-orchestrator-console")
    match = re.search(r"name: Content-Security-Policy\s*\n\s*value: (.+)", route)
    assert match, "Console route must emit its CSP"
    return json.loads(match.group(1))


def api_backend(*allow_origins, hostname="api.example.test"):
    return {"hostname": hostname, "cors": {"allowOrigins": list(allow_origins)}}


def api_cors_origins(manifest):
    policy = resource(manifest, "SecurityPolicy", "platform-orchestrator-backend-gateway")
    match = re.search(r"\n    allowOrigins:\n((?:    - .+\n)+)", policy)
    assert match, "the API SecurityPolicy must emit its CORS origins"
    return [line.removeprefix("    - ") for line in match.group(1).splitlines()]


def normalize_generated_secrets(manifest):
    # Offline renders generate new bootstrap secrets. Normalize only those
    # existing random values so every other resource field remains compared.
    documents = []
    for document in manifest.split("\n---"):
        if "kind: Secret\n" in document:
            document = re.sub(
                r'(\n  (?:password|clientSecret|natsAuthToken|runnerTokenSalt|'
                r'runnerGatewayReceiptKey|ssoStateSecret|superUserToken): )"[^"]+"',
                r'\1"<generated>"', document,
            )
        documents.append(document)
    return "\n---".join(documents)


class ConsolePluginUiCspContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = render()
        assert result.returncode == 0, result.stderr
        cls.stock_manifest = result.stdout

    def test_default_and_empty_list_preserve_stock_policy(self):
        self.assertEqual(console_csp(self.stock_manifest), STOCK_CSP)
        result = render([])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(normalize_generated_secrets(result.stdout),
                         normalize_generated_secrets(self.stock_manifest))

    def test_exact_origins_change_only_console_frame_sources(self):
        origins = ["https://rollouts.example.test", "https://tools.example.test:8443",
                   "https://127.0.0.1:65535"]
        result = render(origins)
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = STOCK_CSP.replace("; worker-src", " " + " ".join(origins) + "; worker-src")
        self.assertEqual(console_csp(result.stdout), expected)
        self.assertEqual(normalize_generated_secrets(result.stdout.replace(expected, STOCK_CSP)),
                         normalize_generated_secrets(self.stock_manifest))

    def test_invalid_origins_and_container_types_fail_closed(self):
        invalid = [
            "https://rollouts.example.test", {}, 0, False,
            [0], [False], [{}], [""], ["https:"], ["http://rollouts.example.test"],
            ["https://*.example.test"], ["https://rollouts.example.test/*"],
            ["https://user:secret@rollouts.example.test"], ["https://rollouts.example.test/"],
            ["https://rollouts.example.test/path"], ["https://rollouts.example.test?query=value"],
            ["https://rollouts.example.test#fragment"], ["https://rollouts.example.test; script-src *"],
            ["https://rollouts.example.test https://attacker.example.test"],
            ["https://rollouts.example.test\r\nX-Injected: yes"], ["https://rollouts.example.test\n"],
            ["https://rollouts.example.test,"], ["https://rollouts.example.test\\evil"],
            ["https://rollouts.example.test%2f"], ["https://Rollouts.example.test"],
            ["https://rollouts.example.test:0"], ["https://rollouts.example.test:443"],
            ["https://rollouts.example.test:08443"], ["https://rollouts.example.test:65536"],
            ["https://-rollouts.example.test"], ["https://rollouts..example.test"],
            ["https://" + "a" * 64 + ".example.test"],
            ["https://" + ".".join(["a" * 63] * 4)],
            ["https://rollouts.example.test"] * 2,
            ["https://console.example.test"], ["https://console.example.test:8443"],
            ["https://127.1"], ["https://127.000.0.1"], ["https://256.0.0.1"],
            ["https://2130706433"], ["https://rollouts.123"],
            ["https://0x7f000001"], ["https://0x"], ["https://0x7f.0x0.0x0.0x1"],
        ]
        for origins in invalid:
            with self.subTest(origins=origins):
                result = render(origins)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("console.gatewayApi.route.pluginUiOrigins", result.stderr)

    def test_invalid_config_is_rejected_even_when_gateway_is_disabled(self):
        result = render(["https://*.example.test"], gateway_enabled=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("console.gatewayApi.route.pluginUiOrigins", result.stderr)


class PluginUiOutsideApiScope(unittest.TestCase):
    """Plugin UIs never share the API session: neither its cookie nor its CORS policy."""

    def assert_refused(self, origins, backend, *fragments, gateway_enabled=True):
        result = render(origins, backend=backend, gateway_enabled=gateway_enabled)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        for fragment in ("console.gatewayApi.route.pluginUiOrigins", *fragments):
            self.assertIn(fragment, result.stderr)

    def test_installations_without_plugin_uis_keep_the_cors_default(self):
        result = render()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(api_cors_origins(result.stdout), ["https://*.platform-orchestrator.local"])

    def test_session_cookie_domain_is_the_api_hostname(self):
        # The API hostname rule below mirrors this cookie scope.
        result = render(backend=api_backend("https://console.example.test"))
        self.assertEqual(result.returncode, 0, result.stderr)
        config = resource(result.stdout, "ConfigMap", "platform-orchestrator-iam-config")
        self.assertIn("\n  SESSION_TOKEN_COOKIE_DOMAIN: api.example.test\n", config)

    def test_origins_outside_the_api_scope_render(self):
        origins = ["https://rollouts.example.test", "https://tools.example-addons.test:8443",
                   "https://example.test", "https://xapi.example.test"]
        result = render(origins, backend=api_backend("https://console.example.test"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(" ".join(origins) + "; worker-src", console_csp(result.stdout))
        self.assertEqual(api_cors_origins(result.stdout), ["https://console.example.test"])

    def test_cors_entries_that_envoy_does_not_match_are_accepted(self):
        cases = [
            ("https://*.example.test", "https://rollouts.example.net"),
            ("https://*.example.test", "https://example.test"),
            ("https://*.example.test", "https://rollouts.example.test:8443"),
            ("http://*.example.test", "https://rollouts.example.test"),
            ("https://rollouts.example.test:8443", "https://rollouts.example.test"),
            ("https://*.example.test", "https://rollouts.example.test.example.net"),
        ]
        for allowed, origin in cases:
            with self.subTest(allowed=allowed, origin=origin):
                result = render([origin], backend=api_backend("https://console.example.test", allowed))
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_origins_the_api_cors_policy_admits_are_refused(self):
        cases = [
            ("https://*.example.test", ["https://rollouts.example.test"]),
            ("https://*.example.test", ["https://tools.example.org", "https://ui.rollouts.example.test"]),
            ("https://*.example.test:8443", ["https://rollouts.example.test:8443"]),
            ("https://*", ["https://rollouts.example.net"]),
            ("*", ["https://rollouts.example.net"]),
            ("https://rollouts.example.net", ["https://rollouts.example.net"]),
        ]
        for allowed, origins in cases:
            origin = origins[-1]
            with self.subTest(allowed=allowed, origin=origin):
                self.assert_refused(
                    origins, api_backend("https://console.example.test", allowed),
                    f'entry "{origin}" matches global.gatewayApi.backend.cors.allowOrigins entry "{allowed}"',
                    "list the exact Console origins in global.gatewayApi.backend.cors.allowOrigins",
                    "serve plugin UIs from a domain that no entry matches",
                )

    def test_chart_default_cors_refuses_plugin_uis_under_its_domain(self):
        self.assert_refused(
            ["https://addons.platform-orchestrator.local"], None,
            'allowOrigins entry "https://*.platform-orchestrator.local"',
        )

    def test_api_hostname_and_its_subdomains_are_refused_on_any_port(self):
        for origin in ["https://api.example.test", "https://api.example.test:8443",
                       "https://rollouts.api.example.test", "https://ui.rollouts.api.example.test:8443"]:
            for hostname in ["api.example.test", "API.Example.test"]:
                with self.subTest(origin=origin, hostname=hostname):
                    self.assert_refused(
                        [origin], api_backend("https://console.example.test", hostname=hostname),
                        f'entry "{origin}" uses the API hostname "api.example.test" '
                        "(global.gatewayApi.backend.hostname) or a subdomain of it",
                        "serve plugin UIs from a hostname outside the API hostname",
                    )

    def test_console_hostname_is_refused_on_any_port(self):
        for origin in ["https://console.example.test", "https://console.example.test:8443"]:
            with self.subTest(origin=origin):
                self.assert_refused(
                    [origin], api_backend("https://console.example.test"),
                    f'entry "{origin}" uses the Console hostname "console.example.test"',
                )

    def test_non_exact_origins_are_refused(self):
        cases = [
            ("https://*.example.net", "exact HTTPS origins"),
            ("https://rollouts.example.net/", "exact HTTPS origins"),
            ("http://rollouts.example.net", "exact HTTPS origins"),
            ("https://rollouts.example.net:443", "omit the default HTTPS port 443"),
        ]
        for origin, reason in cases:
            with self.subTest(origin=origin):
                self.assert_refused([origin], api_backend("https://console.example.test"), reason)

    def test_scope_is_checked_even_when_gateway_is_disabled(self):
        self.assert_refused(["https://rollouts.api.example.test"], api_backend("https://console.example.test"),
                            'API hostname "api.example.test"', gateway_enabled=False)
        self.assert_refused(["https://rollouts.example.test"], api_backend("https://*.example.test"),
                            'allowOrigins entry "https://*.example.test"', gateway_enabled=False)


if __name__ == "__main__":
    unittest.main()
