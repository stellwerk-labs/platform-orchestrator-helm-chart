#!/usr/bin/env python3
"""Sync pinned upstream files from SOURCE_DIRECTORY; --check verifies drift."""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE_COMMIT = '81948d26747a61e5348f0f3c832d017b36a9cb1c'
FILES = {
    'kubernetes.yml': '2b95907f094e7a274647ba2db22bcc2f9397e33836768990dc4e4b39437e2cba',
    'keycloaks.k8s.keycloak.org-v1.yml': '20c51247cb6cbc6158098caabeaf6b429dc8c016e35829f5ddd9c468b7582667',
    'keycloakrealmimports.k8s.keycloak.org-v1.yml': '8d552e1864d78117a07e535479ddb36e16a42b2695726c875f44828e1323edd4',
    'keycloakoidcclients.k8s.keycloak.org-v1.yml': '15d9199822d1918438bd1d093eee3ec8406e7f9d0837c4527fd6da99c63b058a',
    'keycloaksamlclients.k8s.keycloak.org-v1.yml': '7c69d146f610f3c40acf4466518e89615b6fce7ee2a03d75cd93b7a9a7bf259e',
}


def transform_operator(text):
    replacements = {
        'value: quay.io/keycloak/keycloak:26.8.1': (
            'value: {{ .Values.keycloakImage.repository }}:{{ .Values.keycloakImage.tag }}', 2),
        'image: quay.io/keycloak/keycloak-operator:26.8.1': (
            'image: {{ .Values.image.repository }}:{{ .Values.image.tag }}', 1),
        'value: JOSDK_WATCH_CURRENT': ('value: JOSDK_ALL_NAMESPACES', 4),
    }
    for original, (replacement, count) in replacements.items():
        if text.count(original) != count:
            raise ValueError('upstream operator structure changed')
        text = text.replace(original, replacement)
    documents = text.split('---\n')
    bindings = 0
    for index, document in enumerate(documents):
        if '\nkind: RoleBinding\n' in '\n' + document:
            document = document.replace('kind: RoleBinding\n', 'kind: ClusterRoleBinding\n')
            bindings += 1
        if '\nsubjects:\n' in document:
            if '    namespace: keycloak\n' in document:
                document = document.replace('    namespace: keycloak\n', '    namespace: {{ .Release.Namespace }}\n')
            else:
                original = '    name: keycloak-operator\n'
                if document.count(original) != 1:
                    raise ValueError('ambiguous operator binding subject')
                document = document.replace(original, original + '    namespace: {{ .Release.Namespace }}\n')
        documents[index] = document
    if bindings != 5:
        raise ValueError('unexpected operator controller binding inventory')
    return '---\n'.join(documents)


def main():
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] != '--check'):
        raise SystemExit('usage: sync-keycloak-operator.py SOURCE_DIRECTORY [--check]')
    source = Path(sys.argv[1])
    check = len(sys.argv) == 3
    templates = ROOT / 'charts/keycloak-operator/templates'
    for name, expected in FILES.items():
        raw = (source / name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != expected:
            raise ValueError(f'upstream hash mismatch: {name}')
        generated = transform_operator(raw.decode()).encode() if name == 'kubernetes.yml' else raw
        target = templates / name
        if check:
            if target.read_bytes() != generated:
                raise ValueError(f'vendored manifest drift: {name}')
        else:
            target.write_bytes(generated)
    print(f'Keycloak26.8.1 manifests verified at upstream {SOURCE_COMMIT}.')


if __name__ == '__main__':
    main()
