"""Exercise rendered Keycloak server, CRD and cross-namespace Operator contracts."""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


def render(chart):
    raw = subprocess.check_output(['helm', 'template', 'contract', str(ROOT / chart),
        '--namespace', 'operator-contract'], timeout=30)
    encoded = subprocess.check_output(['yq', '-o=json', '.', '-'], input=raw, timeout=30).decode()
    decoder = json.JSONDecoder()
    documents = []
    while encoded.strip():
        document, end = decoder.raw_decode(encoded.lstrip())
        if document:
            documents.append(document)
        encoded = encoded.lstrip()[end:]
    return documents


class KeycloakUpgradeContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.operator = render('charts/keycloak-operator')
        cls.core = render('charts/platform-orchestrator')

    def test_operator_and_fallback_server_use_distinct_pinned_images(self):
        deployment = next(item for item in self.operator if item['kind'] == 'Deployment')
        container = deployment['spec']['template']['spec']['containers'][0]
        self.assertRegex(container['image'], r'^quay\.io/keycloak/keycloak-operator:26\.8\.1@sha256:[a-f0-9]{64}$')
        env = {item['name']: item.get('value') for item in container['env']}
        fallback = env['kc.operator.keycloak.image']
        self.assertRegex(fallback, r'^quay\.io/keycloak/keycloak:26\.8\.1@sha256:[a-f0-9]{64}$')
        self.assertEqual(fallback, env['RELATED_IMAGE_KEYCLOAK'])

    def test_existing_and_new_crd_versions_remain_served(self):
        crds = {item['metadata']['name']: item for item in self.operator
                if item['kind'] == 'CustomResourceDefinition'}
        self.assertEqual(set(crds), {'keycloaks.k8s.keycloak.org',
            'keycloakrealmimports.k8s.keycloak.org', 'keycloakoidcclients.k8s.keycloak.org',
            'keycloaksamlclients.k8s.keycloak.org'})
        for name, crd in crds.items():
            versions = crd['spec']['versions']
            self.assertEqual(sum(bool(version['storage']) for version in versions), 1, name)
            if name in ('keycloaks.k8s.keycloak.org', 'keycloakrealmimports.k8s.keycloak.org'):
                self.assertTrue(any(v['name'] == 'v2alpha1' and v['served'] for v in versions))
                self.assertTrue(any(v['name'] == 'v2beta1' and v['served'] for v in versions))

    def test_controller_bindings_follow_operator_namespace(self):
        bindings = [item for item in self.operator if item['kind'] == 'ClusterRoleBinding']
        self.assertEqual(len(bindings), 6)
        for binding in bindings:
            for subject in binding['subjects']:
                self.assertEqual(subject['namespace'], 'operator-contract')
                self.assertEqual(subject['name'], 'keycloak-operator')
        deployment = next(item for item in self.operator if item['kind'] == 'Deployment')
        controllers = [env['value'] for env in deployment['spec']['template']['spec']['containers'][0]['env']
                       if env['name'].endswith('CONTROLLER_NAMESPACES')]
        self.assertEqual(controllers, ['JOSDK_ALL_NAMESPACES'] * 4)

    def test_core_keeps_legacy_api_and_uses_patched_server(self):
        resource = next(item for item in self.core if item['kind'] == 'Keycloak')
        self.assertEqual(resource['apiVersion'], 'k8s.keycloak.org/v2alpha1')
        self.assertRegex(resource['spec']['image'], r'^quay\.io/keycloak/keycloak:26\.8\.1@sha256:[a-f0-9]{64}$')
        self.assertEqual(resource['spec']['instances'], 1)
        self.assertFalse(resource['spec']['startOptimized'])


if __name__ == '__main__':
    unittest.main()
