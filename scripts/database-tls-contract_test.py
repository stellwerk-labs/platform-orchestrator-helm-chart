#!/usr/bin/env python3
"""Check actual Core TLS values and existing certificate mounts with Helm."""
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ('control-plane', 'data-plane', 'iam')


def render(values=None):
    with tempfile.TemporaryDirectory(prefix='stellwerk-chart-database-tls-') as directory:
        command = ['helm', 'template', 'platform-orchestrator', str(ROOT / 'charts/platform-orchestrator')]
        if values:
            path = Path(directory) / 'values.json'
            path.write_text(json.dumps(values))
            command += ['-f', str(path)]
        return subprocess.check_output(command, text=True, timeout=60).split('\n---')


def resource(documents, kind, name):
    return next(doc for doc in documents if re.search(r'^kind: ' + re.escape(kind) + r'$', doc, re.M)
                and re.search(r'^  name: ' + re.escape(name) + r'$', doc, re.M))


class DatabaseTLSChartTests(unittest.TestCase):
    def test_compatibility_default_and_require_override_reach_every_core_config(self):
        for values, mode in [(None, 'disable'),
                             ({name: {'config': {'DATABASE_SSLMODE': 'require'}} for name in COMPONENTS}, 'require')]:
            documents = render(values)
            for name in COMPONENTS:
                with self.subTest(component=name, mode=mode):
                    config = resource(documents, 'ConfigMap', 'platform-orchestrator-' + name + '-config')
                    self.assertRegex(config, r'(?m)^  DATABASE_SSLMODE: "?' + mode + r'"?$')

    def test_verify_full_uses_existing_read_only_secret_profiles(self):
        profile = {'enabled': True, 'config': {'PGSSLROOTCERT': '/etc/stellwerk/database/ca.crt'},
                   'secretFiles': [{'name': 'database-ca', 'secretName': 'database-ca',
                                    'key': 'ca.crt', 'mountPath': '/etc/stellwerk/database/ca.crt'}]}
        documents = render({name: {'config': {'DATABASE_SSLMODE': 'verify-full'},
                                   'configurationProfiles': {'databaseTLS': profile}} for name in COMPONENTS})
        for name in COMPONENTS:
            with self.subTest(component=name):
                config = resource(documents, 'ConfigMap', 'platform-orchestrator-' + name + '-config')
                self.assertRegex(config, r'(?m)^  DATABASE_SSLMODE: "?verify-full"?$')
                self.assertRegex(config, r'(?m)^  PGSSLROOTCERT: "?/etc/stellwerk/database/ca.crt"?$')
                deployment = resource(documents, 'Deployment', 'platform-orchestrator-' + name)
                self.assertRegex(deployment, r'mountPath: "/etc/stellwerk/database/ca.crt"\n\s+subPath: secret-value\n\s+readOnly: true')
                self.assertRegex(deployment, r'secretName: "?database-ca"?')
                self.assertRegex(deployment, r'key: "?ca\.crt"?')
        with self.assertRaises(StopIteration):
            resource(documents, 'Secret', 'database-ca')


if __name__ == '__main__':
    unittest.main()
