# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

-include .env

ENV ?= local
KIND_CLUSTER_NAME ?= sca-local
ARGOCD_CHART_VERSION ?= 9.5.22
GIT_REPO_URL ?= https://github.com/sca-templates/infra-kubernetes

export KUBECONFIG

##@ Setup

.PHONY: prereqs
prereqs: ## Install the pinned CLI toolchain (kubectl, helm, kind) — idempotent
	bootstrap/prereqs.sh

##@ Cluster

.PHONY: cluster-up
cluster-up: ## Create the local kind cluster from bootstrap/kind-config.yaml
	@[ -f bootstrap/kind-config.yaml ] || { echo 'bootstrap/kind-config.yaml is missing'; exit 1; }
	kind create cluster --name "$(KIND_CLUSTER_NAME)" --config bootstrap/kind-config.yaml --wait 180s

.PHONY: cluster-down
cluster-down: ## Delete the local kind cluster (keeps nothing)
	kind delete cluster --name "$(KIND_CLUSTER_NAME)"

.PHONY: bootstrap
bootstrap: ## Install ArgoCD and apply the Applications for ENV=$(ENV)
	@[ -f argocd/install-values.yaml ] && [ -f "argocd/apps-$(ENV).yaml" ] && [ -f "argocd/root-app-$(ENV).yaml" ] || { echo 'argocd/ manifests are missing'; exit 1; }
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version "$(ARGOCD_CHART_VERSION)" --namespace argocd --values argocd/install-values.yaml --wait
	@echo '── Applying ApplicationSet (GIT_REPO_URL=$(GIT_REPO_URL))'
	sed "s|{{GIT_REPO_URL}}|$(GIT_REPO_URL)|g" "argocd/apps-$(ENV).yaml" | kubectl apply -f -
	@echo '── Applying root Application (GIT_REPO_URL=$(GIT_REPO_URL))'
	sed "s|{{GIT_REPO_URL}}|$(GIT_REPO_URL)|g" "argocd/root-app-$(ENV).yaml" | kubectl apply -f -
	@echo ''
	@echo 'ArgoCD is reconciling. Watch progress with: make status'

##@ Validation

.PHONY: validate
validate: validate-static ## Static suite + live cluster checks
	@echo '=== Live cluster checks ==='
	@kubectl cluster-info >/dev/null 2>&1 || { echo 'No cluster reachable — run make cluster-up && make bootstrap first'; exit 1; }
	kubectl get applications -n argocd
	kubectl get pods -A

.PHONY: validate-static
validate-static: ## Static suite only: markdownlint, yamllint, YAML parse, bash -n
	@echo '=== markdownlint ==='
	npx --yes markdownlint-cli2 "**/*.md"
	@echo '=== YAML parse ==='
	@find . -path ./.git -prune -o -type f \( -name '*.yaml' -o -name '*.yml' \) -print | sort | while read -r f; do \
		case "$$f" in */templates/*) continue ;; esac; \
		npx --yes js-yaml "$$f" >/dev/null && echo "[OK] $$f"; \
	done
	@if command -v yamllint >/dev/null 2>&1; then \
		echo '=== yamllint ==='; yamllint -c .yamllint.yaml .; \
	else \
		echo '=== yamllint ==='; echo 'yamllint not installed locally — skipping (CI runs it)'; \
	fi
	@echo '=== bash -n ==='
	@for f in bootstrap/*.sh; do bash -n "$$f" && echo "[OK] $$f"; done

##@ Operations

.PHONY: status
status: ## Cluster, ArgoCD apps and pod health overview
	@kubectl cluster-info >/dev/null 2>&1 || { echo 'No cluster reachable — run make cluster-up first'; exit 1; }
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
	rm -rf .env .secrets .generated
	rm -f ./*.tgz
	@echo 'Done.'

.PHONY: help
help: ## Show this help
	@awk 'BEGIN { FS = ":.*##"; printf "infra-kubernetes — GitOps source of truth for the sca platform\n\nUsage:\n  make \033[36m<target>\033[0m\n" } /^[a-zA-Z_0-9-]+:.*?## / { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
