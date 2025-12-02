HELM_VERSION ?= 3.12.0
KUBECTL_VERSION ?= 1.28.0
ARGOCD_VERSION ?= 2.8.0

.PHONY: help
help: ## Display this help message
	@echo "PostgreSQL VDB Platform - Makefile Commands"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: validate
validate: ## Validate all Helm charts and Kubernetes manifests
	@echo "Validating Helm charts..."
	@helm lint charts/postgres-vdb
	@echo "Validating Kubernetes manifests..."
	@kubectl apply --dry-run=client -f applications/
	@kubectl apply --dry-run=client -f crds/
	@echo "✓ All validations passed"

.PHONY: template
template: ## Generate templates from Helm charts (dev environment)
	@echo "Generating Helm templates for dev environment..."
	@helm template dev-vdb charts/postgres-vdb \
		-f environments/dev.yaml \
		--namespace postgres-vdbs-dev

.PHONY: template-all
template-all: ## Generate templates for all environments
	@echo "Generating templates for all environments..."
	@for env in dev qa prod; do \
		echo "\n=== Environment: $$env ==="; \
		helm template $${env}-vdb charts/postgres-vdb \
			-f environments/values-$${env}.yaml \
			--namespace postgres-vdbs-$${env}; \
	done

.PHONY: diff
diff: ## Show diff for dev environment (requires helm-diff plugin)
	@helm diff upgrade dev-vdb charts/postgres-vdb \
		-f environments/dev.yaml \
		--namespace postgres-vdbs-dev \
		--allow-unreleased || true

.PHONY: install-dev
install-dev: ## Install dev environment directly with Helm
	@echo "Installing dev environment..."
	@helm upgrade --install dev-vdb charts/postgres-vdb \
		-f environments/dev.yaml \
		--namespace postgres-vdbs-dev \
		--create-namespace
	@echo "✓ Dev environment installed"

.PHONY: install-qa
install-qa: ## Install QA environment directly with Helm
	@echo "Installing QA environment..."
	@helm upgrade --install qa-vdb charts/postgres-vdb \
		-f environments/qa.yaml \
		--namespace postgres-vdbs-qa \
		--create-namespace
	@echo "✓ QA environment installed"

.PHONY: uninstall-dev
uninstall-dev: ## Uninstall dev environment
	@echo "Uninstalling dev environment..."
	@helm uninstall dev-vdb --namespace postgres-vdbs-dev || true
	@kubectl delete namespace postgres-vdbs-dev || true
	@echo "✓ Dev environment uninstalled"

.PHONY: deploy-argocd-apps
deploy-argocd-apps: ## Deploy ArgoCD applications
	@echo "Deploying ArgoCD applications..."
	@kubectl apply -f applications/app-of-apps.yaml -n argocd
	@echo "✓ ArgoCD applications deployed"
	@echo "Monitor with: argocd app list"

.PHONY: install-crds
install-crds: ## Install Custom Resource Definitions
	@echo "Installing CRDs..."
	@kubectl apply -f crds/
	@echo "✓ CRDs installed"
	@kubectl get crds | grep delphix

.PHONY: create-feature
create-feature: ## Create a new feature environment (usage: make create-feature FEATURE=feat-name)
ifndef FEATURE
	@echo "Error: FEATURE variable is required"
	@echo "Usage: make create-feature FEATURE=feat-789-new-api"
	@exit 1
endif
	@echo "Creating feature environment: $(FEATURE)"
	@./scripts/create-feature-env.sh $(FEATURE)

.PHONY: cleanup-feature
cleanup-feature: ## Cleanup a feature environment (usage: make cleanup-feature FEATURE=feat-name)
ifndef FEATURE
	@echo "Error: FEATURE variable is required"
	@echo "Usage: make cleanup-feature FEATURE=feat-789-new-api"
	@exit 1
endif
	@echo "Cleaning up feature environment: $(FEATURE)"
	@./scripts/cleanup-feature-env.sh $(FEATURE)

.PHONY: list-vdbs
list-vdbs: ## List all PostgresVDB resources
	@echo "PostgresVDB Resources:"
	@kubectl get postgresvdb --all-namespaces

.PHONY: list-apps
list-apps: ## List all ArgoCD applications
	@echo "ArgoCD Applications:"
	@argocd app list || echo "ArgoCD CLI not available"

.PHONY: status
status: ## Show status of all environments
	@echo "=== VDB Resources ==="
	@kubectl get postgresvdb --all-namespaces || echo "No VDBs found"
	@echo ""
	@echo "=== ArgoCD Applications ==="
	@argocd app list 2>/dev/null || echo "ArgoCD CLI not available"
	@echo ""
	@echo "=== Namespaces ==="
	@kubectl get namespaces | grep postgres-vdbs || echo "No postgres-vdbs namespaces found"

.PHONY: logs-operator
logs-operator: ## Show PostgresVDB operator logs
	@kubectl logs -n postgres-vdb-operator -l app=postgres-vdb-operator --tail=100 -f

.PHONY: logs-dev
logs-dev: ## Show logs for dev VDB
	@kubectl logs -n postgres-vdbs-dev -l app.kubernetes.io/instance=dev-vdb --tail=100 -f

.PHONY: connect-dev
connect-dev: ## Port-forward to dev database
	@echo "Port-forwarding to dev database..."
	@echo "Connect with: psql -h localhost -p 5432 -U dev_user -d dev_application"
	@kubectl port-forward svc/dev-vdb 5432:5432 -n postgres-vdbs-dev

.PHONY: test-connection
test-connection: ## Test connection to dev database (requires psql)
	@echo "Testing connection to dev database..."
	@kubectl run -it --rm psql-test --image=postgres:16.9 --restart=Never -- \
		psql "postgresql://dev_user:dev_password_123@dev-vdb.postgres-vdbs-dev.svc.cluster.local:5432/dev_application" \
		-c "SELECT version();"

.PHONY: clean
clean: ## Remove all generated files
	@echo "Cleaning generated files..."
	@find . -name "*.generated.yaml" -delete
	@echo "✓ Clean complete"

.PHONY: check-tools
check-tools: ## Check if required tools are installed
	@echo "Checking required tools..."
	@command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "helm not found"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo "git not found"; exit 1; }
	@echo "✓ kubectl: $$(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -n1)"
	@echo "✓ helm: $$(helm version --short)"
	@echo "✓ git: $$(git --version)"
	@command -v argocd >/dev/null 2>&1 && echo "✓ argocd: $$(argocd version --client --short 2>/dev/null | head -n1)" || echo "⚠ argocd CLI not installed (optional)"

.PHONY: setup
setup: check-tools ## Initial setup - validate tools and configuration
	@echo "Running initial setup checks..."
	@make validate
	@echo ""
	@echo "✓ Setup complete!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Update Git repository URLs in applications/"
	@echo "  2. Update source database in charts/postgres-vdb/values.yaml"
	@echo "  3. Update passwords in environment values files"
	@echo "  4. Install CRDs: make install-crds"
	@echo "  5. Deploy ArgoCD apps: make deploy-argocd-apps"

.DEFAULT_GOAL := help
