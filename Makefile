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
	@echo "✓ All validations passed"

.PHONY: template
template: ## Generate templates from Helm charts (dev environment)
	@echo "Generating Helm templates for dev environment..."
	@helm template dev-vdb charts/postgres-vdb \
		-f environments/dev/values.yaml \
		--namespace postgres-vdbs-dev

.PHONY: template-env
template-env: ## Generate templates for specific environment (usage: make template-env ENV=dev)
ifndef ENV
	@echo "Error: ENV variable is required"
	@echo "Usage: make template-env ENV=dev"
	@exit 1
endif
	@echo "Generating Helm templates for $(ENV) environment..."
	@helm template $(ENV)-vdb charts/postgres-vdb \
		-f environments/$(ENV)/values.yaml \
		--namespace postgres-vdbs-$(ENV)

.PHONY: template-all
template-all: ## Generate templates for all environments
	@echo "Generating templates for all environments..."
	@for dir in environments/*/; do \
		env=$$(basename $$dir); \
		echo "\n=== Environment: $$env ==="; \
		helm template $${env}-vdb charts/postgres-vdb \
			-f environments/$${env}/values.yaml \
			--namespace postgres-vdbs-$${env}; \
	done

.PHONY: diff
diff: ## Show diff for dev environment (requires helm-diff plugin)
	@helm diff upgrade dev-vdb charts/postgres-vdb \
		-f environments/dev/values.yaml \
		--namespace postgres-vdbs-dev \
		--allow-unreleased || true

.PHONY: install-dev
install-dev: ## Install dev environment directly with Helm
	@echo "Installing dev environment..."
	@helm upgrade --install dev-vdb charts/postgres-vdb \
		-f environments/dev/values.yaml \
		--namespace postgres-vdbs-dev \
		--create-namespace
	@echo "✓ Dev environment installed"

.PHONY: install-qa
install-qa: ## Install QA environment directly with Helm
	@echo "Installing QA environment..."
	@helm upgrade --install qa-vdb charts/postgres-vdb \
		-f environments/qa/values.yaml \
		--namespace postgres-vdbs-qa \
		--create-namespace
	@echo "✓ QA environment installed"

.PHONY: install-env
install-env: ## Install specific environment directly with Helm (usage: make install-env ENV=dev)
ifndef ENV
	@echo "Error: ENV variable is required"
	@echo "Usage: make install-env ENV=dev"
	@exit 1
endif
	@echo "Installing $(ENV) environment..."
	@helm upgrade --install $(ENV)-vdb charts/postgres-vdb \
		-f environments/$(ENV)/values.yaml \
		--namespace postgres-vdbs-$(ENV) \
		--create-namespace
	@echo "✓ $(ENV) environment installed"

.PHONY: uninstall-dev
uninstall-dev: ## Uninstall dev environment
	@echo "Uninstalling dev environment..."
	@helm uninstall dev-vdb --namespace postgres-vdbs-dev || true
	@kubectl delete namespace postgres-vdbs-dev || true
	@echo "✓ Dev environment uninstalled"

.PHONY: uninstall-env
uninstall-env: ## Uninstall specific environment (usage: make uninstall-env ENV=dev)
ifndef ENV
	@echo "Error: ENV variable is required"
	@echo "Usage: make uninstall-env ENV=dev"
	@exit 1
endif
	@echo "Uninstalling $(ENV) environment..."
	@helm uninstall $(ENV)-vdb --namespace postgres-vdbs-$(ENV) || true
	@kubectl delete namespace postgres-vdbs-$(ENV) || true
	@echo "✓ $(ENV) environment uninstalled"

.PHONY: deploy-argocd-apps
deploy-argocd-apps: ## Deploy ArgoCD applications
	@echo "Deploying ArgoCD applications..."
	@kubectl apply -f applications/app-of-apps.yaml -n argocd
	@echo "✓ ArgoCD applications deployed"
	@echo "Monitor with: argocd app list"

.PHONY: create-feature
create-feature: ## Create a new feature environment (usage: make create-feature FEATURE=feat-name)
ifndef FEATURE
	@echo "Error: FEATURE variable is required"
	@echo "Usage: make create-feature FEATURE=feat-789-new-api"
	@exit 1
endif
	@echo "Creating feature environment: $(FEATURE)"
	@mkdir -p environments/$(FEATURE)
	@echo "Copying template from dev environment..."
	@cp environments/dev/values.yaml environments/$(FEATURE)/values.yaml
	@echo "Updating environment name in values.yaml..."
	@sed -i.bak 's/dev/$(FEATURE)/g' environments/$(FEATURE)/values.yaml && rm environments/$(FEATURE)/values.yaml.bak
	@echo ""
	@echo "✓ Feature environment created at: environments/$(FEATURE)/"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Review and customize: environments/$(FEATURE)/values.yaml"
	@echo "  2. Commit and push to trigger ArgoCD deployment:"
	@echo "     git add environments/$(FEATURE)/"
	@echo "     git commit -m 'Add $(FEATURE) environment'"
	@echo "     git push"
	@echo "  3. Monitor deployment:"
	@echo "     argocd app list --grpc-web | grep $(FEATURE)"
	@echo "     kubectl get postgresvdb -n postgres-vdbs-$(FEATURE)"

.PHONY: create-env
create-env: ## Create a new environment from template (usage: make create-env ENV=stage)
ifndef ENV
	@echo "Error: ENV variable is required"
	@echo "Usage: make create-env ENV=stage"
	@exit 1
endif
	@echo "Creating $(ENV) environment..."
	@mkdir -p environments/$(ENV)
	@echo "Copying template from dev environment..."
	@cp environments/dev/values.yaml environments/$(ENV)/values.yaml
	@echo "Updating environment name in values.yaml..."
	@sed -i.bak 's/dev/$(ENV)/g' environments/$(ENV)/values.yaml && rm environments/$(ENV)/values.yaml.bak
	@echo ""
	@echo "✓ Environment created at: environments/$(ENV)/"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Review and customize: environments/$(ENV)/values.yaml"
	@echo "  2. Commit and push to trigger ArgoCD deployment:"
	@echo "     git add environments/$(ENV)/"
	@echo "     git commit -m 'Add $(ENV) environment'"
	@echo "     git push"
	@echo "  3. Monitor deployment:"
	@echo "     argocd app list --grpc-web | grep $(ENV)"
	@echo "     kubectl get postgresvdb -n postgres-vdbs-$(ENV)"

.PHONY: cleanup-feature
cleanup-feature: ## Cleanup a feature environment (usage: make cleanup-feature FEATURE=feat-name)
ifndef FEATURE
	@echo "Error: FEATURE variable is required"
	@echo "Usage: make cleanup-feature FEATURE=feat-789-new-api"
	@exit 1
endif
	@echo "⚠️  WARNING: This will delete the $(FEATURE) environment and all its resources!"
	@echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
	@sleep 5
	@echo ""
	@echo "Step 1/4: Deleting ArgoCD application with cascade..."
	@argocd app delete postgres-vdb-$(FEATURE) --grpc-web --cascade --wait --timeout 300 2>/dev/null || \
		(echo "⚠️  ArgoCD app not found or already deleted" && exit 0)
	@echo "✓ ArgoCD application deleted"
	@echo ""
	@echo "Step 2/4: Waiting for VDB deletion to complete..."
	@timeout=60; \
	while [ $$timeout -gt 0 ]; do \
		if ! kubectl get postgresvdb -n postgres-vdbs-$(FEATURE) 2>/dev/null | grep -q $(FEATURE)-vdb; then \
			echo "✓ VDB deleted successfully"; \
			break; \
		fi; \
		echo "Waiting for VDB deletion... ($$timeout seconds remaining)"; \
		sleep 5; \
		timeout=$$((timeout - 5)); \
	done; \
	if [ $$timeout -le 0 ]; then \
		echo "⚠️  VDB still exists after timeout, forcing deletion..."; \
		kubectl delete postgresvdb --all -n postgres-vdbs-$(FEATURE) --force --grace-period=0 || true; \
	fi
	@echo ""
	@echo "Step 3/4: Waiting for namespace deletion to complete..."
	@timeout=60; \
	while [ $$timeout -gt 0 ]; do \
		if ! kubectl get namespace postgres-vdbs-$(FEATURE) 2>/dev/null; then \
			echo "✓ Namespace deleted successfully"; \
			break; \
		fi; \
		echo "Waiting for namespace deletion... ($$timeout seconds remaining)"; \
		sleep 5; \
		timeout=$$((timeout - 5)); \
	done; \
	if [ $$timeout -le 0 ]; then \
		echo "⚠️  Namespace still exists after timeout, forcing deletion..."; \
		kubectl delete namespace postgres-vdbs-$(FEATURE) --force --grace-period=0 || true; \
	fi
	@echo ""
	@echo "Step 4/4: Removing environment directory from git..."
	@if [ -d "environments/$(FEATURE)" ]; then \
		git rm -rf environments/$(FEATURE) && \
		git commit -m "Remove $(FEATURE) environment (cleaned up)" && \
		git push && \
		echo "✓ Environment removed from Git and pushed"; \
	else \
		echo "⚠️  Environment directory not found, skipping Git cleanup"; \
	fi
	@echo ""
	@echo "✅ Feature environment deletion complete!"
	@echo ""
	@echo "Verification:"
	@echo "  ArgoCD app: $$(argocd app get postgres-vdb-$(FEATURE) --grpc-web 2>&1 | grep -q 'not found' && echo 'Deleted ✓' || echo 'Still exists ⚠️')"
	@echo "  Namespace:  $$(kubectl get namespace postgres-vdbs-$(FEATURE) 2>&1 | grep -q 'NotFound' && echo 'Deleted ✓' || echo 'Still exists ⚠️')"
	@echo "  VDB:        $$(kubectl get postgresvdb -A 2>&1 | grep -q '$(FEATURE)-vdb' && echo 'Still exists ⚠️' || echo 'Deleted ✓')"

.PHONY: delete-env
delete-env: ## Delete an environment completely via GitOps (usage: make delete-env ENV=stage)
ifndef ENV
	@echo "Error: ENV variable is required"
	@echo "Usage: make delete-env ENV=stage"
	@exit 1
endif
	@echo "⚠️  WARNING: This will delete the $(ENV) environment and all its resources!"
	@echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
	@sleep 5
	@echo ""
	@echo "Removing environment directory from Git and pushing..."
	@if [ -d "environments/$(ENV)" ]; then \
		git rm -rf environments/$(ENV) && \
		git commit -m "Remove $(ENV) environment" && \
		git push && \
		echo "✓ Environment removed from Git and pushed"; \
	else \
		echo "⚠️  Environment directory not found"; \
		exit 1; \
	fi
	@echo ""
	@echo "✅ Deletion initiated!"
	@echo ""
	@echo "ArgoCD ApplicationSet will automatically:"
	@echo "  1. Detect the directory removal (within 3-10 seconds)"
	@echo "  2. Prune the Application CR"
	@echo "  3. Trigger cascade deletion of all resources (VDB, Secrets, etc.)"
	@echo "  4. Clean up the namespace"
	@echo ""
	@echo "Monitor deletion progress with:"
	@echo "  kubectl get application postgres-vdb-$(ENV) -n argocd"
	@echo "  kubectl get postgresvdb -n postgres-vdbs-$(ENV)"
	@echo "  kubectl get namespace postgres-vdbs-$(ENV)"

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
