# Simple Makefile for Helm chart convenience tasks

HELM ?= helm
HELMFILE ?= helmfile
CT ?= ct
HELM_DOCS ?= helm-docs

.PHONY: help lint template helm-check helmfile-check ct-check helm-docs-check docs deploy deploy-local destroy destroy-local add-certs-macos print-keycloak-admin setup-local

help:
	@echo "Available targets:"
	@echo "  lint                 - Run 'ct lint' for all charts"
	@echo "  template             - Render templates with default values"
	@echo "  deploy               - Apply all charts using helmfile"
	@echo "  deploy-local         - Apply all charts using helmfile to a local cluster, e.g. Kind"
	@echo "  destroy              - Destroy all releases using helmfile"
	@echo "  destroy-local        - Destroy all releases using helmfile to a local cluster, e.g. Kind"
	@echo "  create-kind          - Create Kind cluster"
	@echo "  clean-kind           - Delete Kind cluster"
	@echo "  add-certs-macos      - Add self-signed TLS certificates to MacOS keychain"
	@echo "  print-keycloak-admin - Print Keycloak bootstrap admin's credentials"
	@echo "  docs                 - Generate README.md from values.yaml using helm-docs"
	@echo "  setup-local          - Full local setup"

helm-check:
	@command -v $(HELM) >/dev/null 2>&1 || { \
	  echo "Error: '$(HELM)' not found in PATH. Install Helm: https://helm.sh/docs/intro/install/"; \
	  exit 1; \
	}

helmfile-check: helm-check
	@command -v $(HELMFILE) >/dev/null 2>&1 || { \
	  echo "Error: '$(HELMFILE)' not found in PATH. Install Helmfile: https://helmfile.readthedocs.io/en/latest/#installation"; \
	  exit 1; \
	}

ct-check: helm-check
	@command -v $(CT) >/dev/null 2>&1 || { \
	  echo "Error: '$(CT)' not found in PATH. Install Chart Testing: https://github.com/helm/chart-testing/tree/main?tab=readme-ov-file#installation"; \
	  exit 1; \
	}

helm-docs-check:
	@command -v $(HELM_DOCS) >/dev/null 2>&1 || { \
	  echo "Error: '$(HELM_DOCS)' not found in PATH. Install helm-docs: https://github.com/norwoodj/helm-docs#installation"; \
	  exit 1; \
	}

docs: helm-docs-check
	HELM_DOCS=$(HELM_DOCS) bash scripts/generate-docs.sh

lint: ct-check
	$(HELMFILE) deps
	$(CT) lint --all --config .ct.yaml

template: helmfile-check
	$(HELMFILE) deps
	$(HELMFILE) template

deploy: helmfile-check
	$(HELMFILE) deps
	$(HELMFILE) sync

destroy: helmfile-check
	$(HELMFILE) destroy

check-context:
	@current_context=$$(kubectl config current-context); \
	if [ "$$current_context" != "kind-test-orch" ]; then \
		echo "Error: Current context is '$$current_context', expected 'kind-test-orch'"; \
		exit 1; \
	fi; \
	echo "✓ Correct context: $$current_context"

deploy-local: check-context helmfile-check
	$(HELMFILE) deps
	$(HELMFILE) -e local sync

destroy-local: check-context helmfile-check
	$(HELMFILE) destroy -e local sync

create-kind:
	kind create cluster -n test-orch --config kind-config.yaml

clean-kind:
	kind delete cluster -n test-orch

add-certs-macos:
	@bash scripts/add-certs-macos.sh

print-keycloak-admin:
	@bash scripts/print-keycloak-admin-cred.sh

setup-local:
	$(MAKE) create-kind
	$(MAKE) deploy-local
	$(MAKE) add-certs-macos
