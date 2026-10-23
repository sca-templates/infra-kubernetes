# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

-include .env

ENV ?= local
ARGOCD_CHART_VERSION ?= 9.5.22
GIT_REPO_URL ?= https://github.com/sca-templates/infra-kubernetes
GIT_TARGET_BRANCH ?= main

export KUBECONFIG

##@ Setup

.PHONY: prereqs
prereqs: ## Install the pinned CLI toolchain (kubectl, helm) — idempotent
	bootstrap/sca.sh prereqs

.PHONY: doctor
doctor: ## Read-only platform health check (toolchain, cluster, ArgoCD apps, seam)
	@[ -f bootstrap/sca.sh ] || { echo 'bootstrap/sca.sh is missing'; exit 1; }
	bootstrap/sca.sh doctor

.PHONY: install-cli
install-cli: ## Symlink bootstrap/sca.sh into ~/.local/bin/sca for direct use
	@mkdir -p "${HOME}/.local/bin"
	ln -sfn "$(CURDIR)/bootstrap/sca.sh" "${HOME}/.local/bin/sca"
	@echo "sca is now available as: sca prereqs | sca doctor | sca version"

##@ Cluster

.PHONY: argocd-up
argocd-up: ## Install or upgrade ArgoCD from argocd/install-values.yaml (no apps)
	@[ -f argocd/install-values.yaml ] || { echo 'argocd/install-values.yaml is missing'; exit 1; }
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	# Warm the cluster node with the chart images so a throttled public registry
	# is not on the critical path (see bootstrap/preload-chart-images.sh).
	bootstrap/preload-chart-images.sh argo-cd https://argoproj.github.io/argo-helm "$(ARGOCD_CHART_VERSION)" --namespace argocd --values argocd/install-values.yaml
	helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version "$(ARGOCD_CHART_VERSION)" --namespace argocd --values argocd/install-values.yaml --wait --timeout 15m || { \
		echo '[FAIL] argocd-up failed — collecting diagnostics into .generated/'; \
		bootstrap/collect-argocd-diagnostics.sh; \
		exit 1; \
	}

.PHONY: bootstrap
bootstrap: argocd-up ## Install ArgoCD and apply the Applications for ENV=$(ENV)
	@[ -f "argocd/apps-$(ENV).yaml" ] || { echo "argocd/apps-$(ENV).yaml is missing"; exit 1; }
	@[ -f "argocd/postgres-app-$(ENV).yaml" ] || { echo "argocd/postgres-app-$(ENV).yaml is missing"; exit 1; }
	@[ -f "argocd/kafka-$(ENV).yaml" ] || { echo "argocd/kafka-$(ENV).yaml is missing"; exit 1; }
	# The Makefile seeds the catalog wiring: argocd/apps-$(ENV).yaml (the platform
	# ApplicationSet) and the dedicated Applications argocd/kong-$(ENV).yaml,
	# argocd/linkerd-$(ENV).yaml, argocd/postgres-app-$(ENV).yaml and
	# argocd/kafka-$(ENV).yaml are applied with
	# {{GIT_REPO_URL}}/{{GIT_TARGET_BRANCH}} resolved here, so the generated
	# children track the ref under test (the PR head in the CI smoke, main
	# otherwise). The root Application owns only the services registry
	# (argocd/services-$(ENV).yaml), never these, so there is a single owner.
	@echo '── Preloading catalog images for ENV=$(ENV)'
	bootstrap/preload-chart-images.sh --catalog "$(ENV)"
	@echo '── Applying platform ApplicationSet + Kong + Linkerd + postgres-app + Kafka (GIT_REPO_URL=$(GIT_REPO_URL), GIT_TARGET_BRANCH=$(GIT_TARGET_BRANCH))'
	sed -e "s|{{GIT_REPO_URL}}|$(GIT_REPO_URL)|g" -e "s|{{GIT_TARGET_BRANCH}}|$(GIT_TARGET_BRANCH)|g" "argocd/apps-$(ENV).yaml" | kubectl apply -f -
	sed -e "s|{{GIT_REPO_URL}}|$(GIT_REPO_URL)|g" -e "s|{{GIT_TARGET_BRANCH}}|$(GIT_TARGET_BRANCH)|g" "argocd/kong-$(ENV).yaml" | kubectl apply -f -
	sed -e "s|{{GIT_REPO_URL}}|$(GIT_REPO_URL)|g" -e "s|{{GIT_TARGET_BRANCH}}|$(GIT_TARGET_BRANCH)|g" "argocd/linkerd-$(ENV).yaml" | kubectl apply -f -
	sed -e "s|{{GIT_REPO_URL}}|$(GIT_REPO_URL)|g" -e "s|{{GIT_TARGET_BRANCH}}|$(GIT_TARGET_BRANCH)|g" "argocd/postgres-app-$(ENV).yaml" | kubectl apply -f -
	sed -e "s|{{GIT_REPO_URL}}|$(GIT_REPO_URL)|g" -e "s|{{GIT_TARGET_BRANCH}}|$(GIT_TARGET_BRANCH)|g" "argocd/kafka-$(ENV).yaml" | kubectl apply -f -
	@if [ -f "argocd/root-app-$(ENV).yaml" ]; then \
		echo '── Applying root Application (services registry owner)'; \
		sed -e "s|{{GIT_REPO_URL}}|$(GIT_REPO_URL)|g" -e "s|{{GIT_TARGET_BRANCH}}|$(GIT_TARGET_BRANCH)|g" "argocd/root-app-$(ENV).yaml" | kubectl apply -f -; \
	fi
	@echo ''
	@echo 'ArgoCD is reconciling. Watch progress with: make status'

##@ Validation

.PHONY: validate
validate: validate-static ## Static suite + live cluster checks
	@echo '=== Live cluster checks ==='
	@kubectl cluster-info >/dev/null 2>&1 || { echo 'No cluster reachable — run make eks-up && make bootstrap first'; exit 1; }
	kubectl get applications -n argocd
	kubectl get pods -A

.PHONY: validate-static
validate-static: ## Static suite only: markdownlint, yamllint, YAML parse, bash -n
	@echo '=== markdownlint ==='
	npx --yes markdownlint-cli2 "**/*.md"
	@echo '=== YAML parse ==='
	@find . -path ./.git -prune -o -type f \( -name '*.yaml' -o -name '*.yml' \) -print | sort | while read -r f; do \
		case "$$f" in */templates/*) continue ;; esac; \
		npx --yes js-yaml@4.1.0 "$$f" >/dev/null && echo "[OK] $$f" || { echo "[FAIL] $$f"; exit 1; }; \
	done
	@if command -v yamllint >/dev/null 2>&1; then \
		echo '=== yamllint ==='; yamllint -c .yamllint.yaml .; \
	else \
		echo '=== yamllint ==='; echo 'yamllint not installed locally — skipping (CI runs it)'; \
	fi
	@echo '=== bash -n ==='
	@for f in bootstrap/*.sh; do bash -n "$$f" && echo "[OK] $$f"; done

COMPONENT ?=
CLOUD_PROVIDER ?= aws

##@ Cloud (emulator — dev/CI tooling, docs/ci-cd.md)

.PHONY: cloud-up
cloud-up: ## Start the cloud emulator and publish it to the cluster
	@[ -n "$(CLOUD_PROVIDER)" ] || { echo 'Usage: make cloud-up CLOUD_PROVIDER=<aws>'; exit 1; }
	bootstrap/cloud-emulator.sh up "$(CLOUD_PROVIDER)"

.PHONY: cloud-down
cloud-down: ## Stop the cloud emulator and unpublish it from the cluster
	bootstrap/cloud-emulator.sh down "$(CLOUD_PROVIDER)"

.PHONY: cloud-status
cloud-status: ## Report cloud-emulator reachability (host edge + in-cluster Service)
	bootstrap/cloud-emulator.sh status "$(CLOUD_PROVIDER)"

##@ EKS substrate (emulator — dev/CI tooling, docs/ci-cd.md)

.PHONY: eks-up
eks-up: ## Start Floci in EKS mode: create the emulated EKS cluster and point kubectl at it
	bootstrap/eks-emulator.sh up

.PHONY: eks-down
eks-down: ## Delete the emulated EKS cluster, IAM user and kubeconfig context
	bootstrap/eks-emulator.sh down

.PHONY: eks-status
eks-status: ## Report the emulated EKS cluster status and its nodes
	bootstrap/eks-emulator.sh status

##@ Smoke

.PHONY: smoke
smoke: ## Smoke a deployed component: make smoke COMPONENT=cert-manager
	@[ -n "$(COMPONENT)" ] || { echo 'Usage: make smoke COMPONENT=<component> (cert-manager, vault, external-secrets, linkerd-crds, linkerd, cloudnative-pg, strimzi, redis-operator, kong, postgres-app, kafka, cloud, eks)'; exit 1; }
	bootstrap/smoke-target.sh "$(COMPONENT)"

##@ Local Git serve

.PHONY: local-git-up
local-git-up: ## Stand up the fully-local git serve (bare mirror + git daemon + .env seam)
	GIT_TARGET_BRANCH="$(GIT_TARGET_BRANCH)" bootstrap/local-git-up.sh

.PHONY: local-git-update
local-git-update: ## Mirror local HEAD into the local git serve (after each commit)
	GIT_REPO_URL="$(GIT_REPO_URL)" GIT_TARGET_BRANCH="$(GIT_TARGET_BRANCH)" bootstrap/local-git-update.sh

.PHONY: local-git-down
local-git-down: ## Stop the local git serve (keeps the bare mirror)
	bootstrap/local-git-down.sh

##@ Operations

.PHONY: status
status: ## Cluster, ArgoCD apps and pod health overview
	@kubectl cluster-info >/dev/null 2>&1 || { echo 'No cluster reachable — run make eks-up first'; exit 1; }
	@echo '=== Nodes ==='
	kubectl get nodes -o wide
	@echo ''
	@echo '=== ArgoCD applications ==='
	@kubectl get applications -n argocd 2>/dev/null || echo 'argocd not installed yet — run make bootstrap'
	@echo ''
	@echo '=== Pods not Running/Completed ==='
	@kubectl get pods -A --no-headers | grep -vE 'Running|Completed' || echo 'all healthy'

.PHONY: port-forward
port-forward: ## Reach a platform UI/API locally: make port-forward APP=argocd|vault|keycloak|grafana|prometheus|tempo|postgres|kong-admin|minio
	@[ -n "$(APP)" ] || { echo 'Usage: make port-forward APP=<name> (argocd, vault, keycloak, grafana, prometheus, tempo, postgres, kong-admin, minio)'; exit 1; }
	@case "$(APP)" in \
		argocd)     ns=argocd;        svc=argocd-server;                   ports=8443:443 ;; \
		vault)      ns=vault;         svc=vault;                           ports=8200:8200 ;; \
		keycloak)   ns=keycloak;      svc=keycloak;                        ports=8080:80 ;; \
		grafana)    ns=observability; svc=kube-prometheus-stack-grafana;   ports=3000:80 ;; \
		prometheus) ns=observability; svc=kube-prometheus-stack-prometheus; ports=9090:9090 ;; \
		tempo)      ns=tempo;         svc=tempo;                           ports=3200:3200 ;; \
		postgres)   ns=data;          svc=postgres-app-rw;                 ports=5432:5432 ;; \
		kong-admin) ns=kong;          svc=kong-admin;                      ports=8001:8001 ;; \
		minio)      ns=minio;         svc=minio-console;                   ports=9001:9001 ;; \
		*) echo "ERROR: unknown APP '$(APP)'"; exit 1 ;; \
	esac; \
	echo "Forwarding $$ns/$$svc → http://localhost:$${ports%%:*}"; \
	kubectl -n "$$ns" port-forward "svc/$$svc" "$$ports"

##@ Housekeeping

.PHONY: clean
clean: ## Remove local state (.env, .secrets/, generated artifacts)
	rm -rf .env .secrets .generated .git-local
	rm -f ./*.tgz
	@echo 'Done.'

.PHONY: help
help: ## Show this help
	@awk 'BEGIN { FS = ":.*##"; printf "infra-kubernetes — GitOps source of truth for the sca platform\n\nUsage:\n  make \033[36m<target>\033[0m\n" } /^[a-zA-Z_0-9-]+:.*?## / { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
