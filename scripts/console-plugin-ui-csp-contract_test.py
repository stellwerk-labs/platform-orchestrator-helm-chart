#!/usr/bin/env python3
"""Exercise the real Helm-rendered Console CSP and fail-closed origin validation."""
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


def render(origins=None, *, gateway_enabled=True):
    values = {"global": {"gatewayApi": {
        "enabled": gateway_enabled, "frontend": {"hostname": "console.example.test"},
    }}}
    if origins is not None:
        values["console"] = {"gatewayApi": {"route": {"pluginUiOrigins": origins}}}
    with tempfile.TemporaryDirectory(prefix="console-plugin-csp-") as directory:
        value_file = Path(directory) / "values.json"
        value_file.write_text(json.dumps(values), encoding="utf-8")
        return subprocess.run(
            ["helm", "template", "platform-orchestrator", str(CHART), "-f", str(value_file)],
            text=True, capture_output=True, timeout=30, check=False,
        )


def console_csp(manifest):
    route = next(
        document for document in manifest.split("\n---")
        if "kind: HTTPRoute\n" in document
        and "\n  name: platform-orchestrator-console\n" in document
    )
    match = re.search(r"name: Content-Security-Policy\s*\n\s*value: (.+)", route)
    assert match, "Console route must emit its CSP"
    return json.loads(match.group(1))


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


if __name__ == "__main__":
    unittest.main()
