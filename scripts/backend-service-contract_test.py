#!/usr/bin/env python3
"""Check real Helm Service identities, headless mode and unchanged peers."""
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CHART = ROOT / "charts/platform-orchestrator"


def render(values=None):
    with tempfile.TemporaryDirectory(prefix="backend-service-contract-") as directory:
        path = Path(directory) / "values.json"
        path.write_text(json.dumps(values or {}), encoding="utf-8")
        result = subprocess.run(
            ["helm", "template", "platform-orchestrator", str(CHART),
             "--namespace", "platform-orchestrator", "-f", str(path)],
            capture_output=True, text=True, timeout=30, check=True,
        )
    return [document for document in result.stdout.split("\n---")
            if re.search(r"^kind: ", document, re.M)]


def identity(document):
    api = re.search(r"^apiVersion: (.+)$", document, re.M).group(1)
    kind = re.search(r"^kind: (.+)$", document, re.M).group(1)
    metadata = re.search(r"^metadata:\n((?:[ \t].*\n|\n)+)", document, re.M).group(1)
    name = re.search(r"^  name: (.+)$", metadata, re.M).group(1)
    namespace = re.search(r"^  namespace: (.+)$", metadata, re.M)
    return api, kind, namespace.group(1) if namespace else "", name


def unique_resources(documents):
    resources = {}
    for document in documents:
        key = identity(document)
        if key in resources:
            raise ValueError("duplicate rendered resource identity")
        resources[key] = document
    return resources


def named(documents, kind, name):
    matches = [document for document in documents if identity(document)[1::2] == (kind, name)]
    if len(matches) != 1:
        raise ValueError("expected exactly one rendered resource")
    return matches[0]


def normalize_generated_secrets(document):
    if identity(document)[1] == "Secret":
        document = re.sub(
            r'(\n  (?:password|clientSecret|natsAuthToken|runnerTokenSalt|'
            r'runnerGatewayReceiptKey|ssoStateSecret|superUserToken): )"[^"]+"',
            r'\1"<generated>"', document,
        )
    return document


class BackendServiceContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.default = render()

    def assert_service(self, documents, name, component, *, headless, port=8080, target_port=8080,
                       service_type="ClusterIP"):
        document = named(documents, "Service", name)
        expected = (
            f"spec:\n  type: {service_type}\n"
            + ("  clusterIP: None\n" if headless else "")
            + "  selector:\n"
            + f"    app.kubernetes.io/name: {component}\n"
            + "    app.kubernetes.io/instance: platform-orchestrator\n"
            + "  ports:\n    - name: http\n"
            + f"      port: {port}\n      targetPort: {target_port}\n      protocol: TCP"
        )
        self.assertEqual(document.split("\nspec:\n", 1)[1].strip(),
                         expected.removeprefix("spec:\n").strip())

    def test_default_whole_chart_has_unique_identities_and_original_dns(self):
        unique_resources(self.default)
        self.assert_service(self.default, "platform-orchestrator-data-plane", "data-plane", headless=True)
        for component in ("control-plane", "iam"):
            self.assert_service(self.default, "platform-orchestrator-" + component, component, headless=False)
        config = named(self.default, "ConfigMap", "platform-orchestrator-data-plane-config")
        self.assertIn("INTERNAL_DATAPLANE_HOSTNAME: platform-orchestrator-data-plane.platform-orchestrator.svc.cluster.local", config)
        config = named(self.default, "ConfigMap", "platform-orchestrator-control-plane-config")
        self.assertIn("DATA_PLANE_URL: http://platform-orchestrator-data-plane:8080", config)
        self.assertFalse(any(identity(doc)[3] == "platform-orchestrator-data-plane-headless"
                             for doc in self.default))

    def test_explicit_false_changes_only_original_service_mode(self):
        disabled = render({"data-plane": {"service": {"createHeadless": False}}})
        self.assert_service(disabled, "platform-orchestrator-data-plane", "data-plane", headless=False)
        old, new = unique_resources(self.default), unique_resources(disabled)
        self.assertEqual(old.keys(), new.keys())
        for key in old:
            if key[1:] != ("Service", "", "platform-orchestrator-data-plane"):
                self.assertEqual(normalize_generated_secrets(old[key]), normalize_generated_secrets(new[key]), key)

    def test_both_modes_preserve_custom_name_ports_and_selectors(self):
        for headless in (False, True):
            with self.subTest(headless=headless):
                documents = render({"data-plane": {"fullnameOverride": "custom-data-plane",
                    "service": {"createHeadless": headless, "type": "NodePort", "port": 9000, "targetPort": 9100}}})
                unique_resources(documents)
                self.assert_service(documents, "custom-data-plane", "data-plane", headless=headless,
                    port=9000, target_port=9100, service_type="ClusterIP" if headless else "NodePort")
                for component in ("control-plane", "iam"):
                    self.assert_service(documents, "platform-orchestrator-" + component, component, headless=False)

    def test_explicit_true_is_available_to_other_backends_without_new_names(self):
        documents = render({"control-plane": {"service": {"createHeadless": True}},
                            "iam": {"service": {"createHeadless": True}}})
        unique_resources(documents)
        for component in ("control-plane", "data-plane", "iam"):
            self.assert_service(documents, "platform-orchestrator-" + component, component, headless=True)

    def test_duplicate_detector_rejects_real_rendered_service_copy(self):
        service = named(self.default, "Service", "platform-orchestrator-control-plane")
        with self.assertRaisesRegex(ValueError, "duplicate rendered resource identity"):
            unique_resources(self.default + [service])


if __name__ == "__main__":
    unittest.main()
