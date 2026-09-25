# Offline-first Makefile. Nothing here talks to AWS unless you run plan/apply/destroy
# explicitly, and even then apply/destroy ask for confirmation.
SHELL := /usr/bin/env bash
TOOLS := scripts/tools.sh
ENV ?= dev

TF_DIRS := bootstrap $(wildcard modules/*) $(wildcard envs/*) tests/render
CHART_DIRS := $(wildcard k8s/charts/*)

.PHONY: check fmt fmt-check validate test lint scan helm-check render-test help \
        bootstrap plan apply destroy deploy rollback cost \
        k8s-up k8s-deploy k8s-down

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  %-14s %s\n", $$1, $$2}'

check: fmt-check validate test lint scan render-test helm-check ## All offline checks (no AWS access needed)
	@echo "✔ all offline checks passed"

fmt: ## Format all Terraform
	$(TOOLS) terraform fmt -recursive

fmt-check: ## Fail if any Terraform is unformatted
	$(TOOLS) terraform fmt -recursive -check -diff

validate: ## terraform init -backend=false && validate in every stack/module
	@set -e; for d in $(TF_DIRS); do \
	  echo "== validate $$d"; \
	  (cd $$d && $(CURDIR)/$(TOOLS) terraform init -backend=false -input=false -no-color >/dev/null \
	          && $(CURDIR)/$(TOOLS) terraform validate -no-color); \
	done

test: ## terraform test (mocked AWS provider) for modules that have tests/
	@set -e; for d in $(dir $(wildcard modules/*/tests/*.tftest.hcl)); do \
	  m=$${d%tests/}; echo "== test $$m"; \
	  (cd $$m && $(CURDIR)/$(TOOLS) terraform init -backend=false -input=false >/dev/null \
	          && $(CURDIR)/$(TOOLS) terraform test -no-color | tail -1); \
	done

lint: ## tflint (recommended preset + AWS ruleset)
	$(TOOLS) tflint --init >/dev/null
	$(TOOLS) tflint --recursive --config=/repo/.tflint.hcl

scan: ## checkov IaC security scan (findings we accept are skipped inline with a reason)
	$(TOOLS) checkov -d . --framework terraform github_actions --quiet --compact \
	  --skip-path .tools --skip-path .terraform --skip-path k8s

render-test: ## Render host templates; shellcheck, compose config, nginx -t
	scripts/test-render.sh

helm-check: ## helm lint + render + kubeconform + checkov on rendered manifests
	@set -e; mkdir -p .tools/rendered; for c in $(CHART_DIRS); do \
	  n=$$(basename $$c); echo "== helm $$c"; \
	  $(TOOLS) helm lint $$c --strict -f $$c/ci/ci-values.yaml; \
	  $(TOOLS) helm template ci $$c -n ci -f $$c/ci/ci-values.yaml > .tools/rendered/$$n.yaml; \
	  $(TOOLS) kubeconform -strict -summary -ignore-missing-schemas - < .tools/rendered/$$n.yaml; \
	done
	@# Accepted k8s findings (reasons in docs/security.md#kubernetes):
	@#   K8S_15/43 immutable git-SHA tags instead of Always/digest pinning; K8S_35 apps read config from env;
	@#   K8S_11 no CPU limits on purpose (CFS throttling); K8S_9 workers serve no traffic (no readiness);
	@#   K8S_8 celery beat has no health endpoint (singleton, restarts on exit).
	$(TOOLS) checkov -d .tools/rendered --framework kubernetes --quiet --compact \
	  --skip-check CKV_K8S_15,CKV_K8S_43,CKV_K8S_35,CKV_K8S_11,CKV_K8S_9,CKV_K8S_8

# ---------------------------------------------------------------------------
# Targets below touch real AWS. Read docs/runbook.md first.
# ---------------------------------------------------------------------------
bootstrap: ## One-time: state bucket, lock table, GitHub OIDC provider
	cd bootstrap && terraform init && terraform apply

plan: ## terraform plan ENV=dev|staging|prod-like
	cd envs/$(ENV) && terraform init -backend-config=backend.hcl -input=false && terraform plan -out=tfplan

apply: ## terraform apply the saved plan (asks to confirm)
	@read -p "Apply saved plan to $(ENV)? Type the env name: " c && [ "$$c" = "$(ENV)" ]
	cd envs/$(ENV) && terraform apply tfplan

destroy: ## Tear an environment down completely
	scripts/teardown.sh $(ENV)

deploy: ## Deploy image: make deploy ENV=staging IMAGE_TAG=<git sha>
	scripts/deploy.sh $(ENV) $(IMAGE_TAG)

rollback: ## Roll back: make rollback ENV=staging TO=<previous sha>
	scripts/rollback.sh $(ENV) $(TO)

cost: ## Estimated monthly cost (infracost, estimate only)
	scripts/cost-estimate.sh $(ENV)

k8s-up: ## Create local kind cluster 'cil-lab'
	scripts/k8s.sh up

k8s-deploy: ## Install both Helm charts into kind
	scripts/k8s.sh deploy

k8s-down: ## Delete the kind cluster
	scripts/k8s.sh down
