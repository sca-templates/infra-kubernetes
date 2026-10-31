#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-ci.sh — cluster-smoke framework for `pr-cluster.yml` (Phase 1).
# Encapsulates the boot → apply → wait → run → diagnose → teardown cycle the
# cluster smoke needs, so each component only adds its own smoke command in
# `bootstrap/smoke-<component>.sh` (dispatched via smoke-target.sh).
#
# There is a single substrate: Floci's emulated EKS (a real k3s node;
# bootstrap/eks-emulator.sh). The framework boots the *full* platform through
# the real app-of-apps (`make bootstrap ENV=local`, `<name>-local`), converges
# every catalog Application, seeds Vault, and then runs the component smokes for
# the touched components plus the EKS/ECR and cloud integration smokes.
#
# Ordering matters for convergence: Applications are gated on `Synced` first
# (any health), then Vault is seeded/unsealed — it is born sealed, so it can
# only report Healthy after `make smoke COMPONENT=vault` ran — and only then is
# the whole platform gated on `Synced/Healthy`.
#
# More than one component can be smoked in a single run: `<component>` is a
# comma-separated list, the cluster is booted once, the cloud emulator is
# brought up once, each component is smoked in turn, and teardown runs once.
#
# Usage:
#   bootstrap/smoke-ci.sh <component[,component...]> <ref> [--keep] [--no-cluster] [--no-cloud]
#   <component>  component(s) to smoke (maps to bootstrap/smoke-<c>.sh); `cloud`
#                and `eks` are smoke targets with no ArgoCD Application
#   <ref>        git ref (branch/sha) the ArgoCD Applications track
#   --keep       do not delete the cluster on exit (diagnosis)
#   --no-cluster skip eks-up (use an existing, bootstrapped cluster)
#   --no-cloud   skip the cloud-integration smoke (SMOKE_CLOUD=0 does the same)
set -euo pipefail

# Load the local `.env` seam if present (same behaviour as bootstrap/sca.sh):
# KEY=value lines become shell variables here, so SMOKE_CLOUD / SMOKE_TIMEOUT
# knobs set in `.env` reach this framework without needing `export`.
for _sca_env in "$(dirname "$0")/../.env" ".env"; do
  if [ -f "$_sca_env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$_sca_env"
    break
  fi
done
unset _sca_env

# shellcheck source=bootstrap/versions.sh
. "$(dirname "$0")/versions.sh"

components_raw="${1:-}"
ref="${2:-}"
KEEP_CLUSTER=0
BOOT_CLUSTER=1
CLOUD_ON=1
if [ -n "${SMOKE_CLOUD:-}" ] && [ "${SMOKE_CLOUD}" = "0" ]; then
  CLOUD_ON=0
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --keep) KEEP_CLUSTER=1 ;;
    --no-cluster) BOOT_CLUSTER=0 ;;
    --no-cloud) CLOUD_ON=0 ;;
    --*) echo "ERROR: unknown flag '$1'" >&2; exit 2 ;;
  esac
  shift
done

[ -n "$components_raw" ] || { echo "ERROR: usage: $0 <component[,component...]> <ref> [--keep] [--no-cluster] [--no-cloud]" >&2; exit 2; }
[ -n "$ref" ] || { echo "ERROR: <ref> is required (head branch/sha for the ArgoCD Applications)" >&2; exit 2; }

# Split the comma-separated list into an array (commas -> spaces, then word
# split); component names never contain whitespace.
COMPONENTS=()
for _c in ${components_raw//,/ }; do
  [ -n "$_c" ] && COMPONENTS+=("$_c")
done
unset _c
[ "${#COMPONENTS[@]}" -gt 0 ] || { echo "ERROR: no components resolved from '${components_raw}'" >&2; exit 2; }

# `cloud` and `eks` are smoke targets, not ArgoCD Applications: they never go
# through the Application wait. Everything else is an Application rendered by
# the platform ApplicationSet.
APP_COMPONENTS=()
HAS_CLOUD=0
for c in "${COMPONENTS[@]}"; do
  case "$c" in
    cloud) HAS_CLOUD=1 ;;
    eks) ;;
    *) APP_COMPONENTS+=("$c") ;;
  esac
done

# The cloud emulator is the EKS substrate itself, so it is always running here;
# --no-cloud / SMOKE_CLOUD=0 only skips the cloud-integration smoke. Asking for
# `component=cloud` while skipping it is contradictory.
if [ "${HAS_CLOUD}" = "1" ] && [ "${CLOUD_ON}" != "1" ]; then
  echo "ERROR: component=cloud needs the cloud smoke — drop --no-cloud / SMOKE_CLOUD=0" >&2
  exit 2
fi

# Platform Applications, read from the repo so a newly-landed component is
# covered for free: infrastructure/<c> → <c>-local.
CATALOG=()
for d in infrastructure/*/; do
  [ -d "$d" ] || continue
  c="${d%/}"; c="${c##*/}"
  CATALOG+=("$c")
done

STATE_DIR=".generated"
TIMEOUT="${SMOKE_TIMEOUT:-1200}"
POLL="${SMOKE_POLL:-10}"
APP_SUFFIX="local"
APPSET_NAME="platform-local"

mkdir -p "${STATE_DIR}"

cleanup() {
  if [ "${KEEP_CLUSTER}" = "1" ]; then
    echo "── smoke-ci: keeping the EKS substrate (--keep) — remove with: make eks-down"
  elif [ "${BOOT_CLUSTER}" = "1" ]; then
    echo "── smoke-ci: tearing down the EKS substrate"
    make eks-down 2>/dev/null || true
  else
    echo "── smoke-ci: --no-cluster, leaving the cluster untouched"
  fi
}
trap cleanup EXIT

diagnose() {
  local app c pod ready
  for c in "${APP_COMPONENTS[@]}"; do
    app="${c}-${APP_SUFFIX}"
    echo "── diagnose: Application/${app}"
    kubectl get application "${app}" -n argocd -o yaml 2>/dev/null | tee "${STATE_DIR}/${app}-diagnose.yaml" || true
    echo "── diagnose: ${app} status.conditions"
    kubectl get application "${app}" -n argocd -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}' 2>/dev/null || true
    echo "── diagnose: ${app} operationState"
    kubectl get application "${app}" -n argocd -o jsonpath='{.status.operationState.phase}{" — "}{.status.operationState.message}{"\n"}' 2>/dev/null || true
    echo "── diagnose: ${app} managed resources (status.resources)"
    kubectl get application "${app}" -n argocd -o jsonpath='{range .status.resources[*]}{.kind}/{.namespace}/{.name} {.status}{"\n"}{end}' 2>/dev/null || true
    echo "── diagnose: ${app} syncResult resources"
    kubectl get application "${app}" -n argocd -o jsonpath='{range .status.operationState.syncResult.resources[*]}{.kind}/{.namespace}/{.name} {.status} {.message}{"\n"}{end}' 2>/dev/null || true
  done
  echo "── diagnose: ApplicationSet/${APPSET_NAME}"
  kubectl get applicationset "${APPSET_NAME}" -n argocd -o yaml 2>/dev/null | tee "${STATE_DIR}/${APPSET_NAME}-diagnose.yaml" || true
  echo "── diagnose: pods (all namespaces not Running/Completed)"
  kubectl get pods -A --no-headers 2>/dev/null | grep -vE 'Running|Completed' || true
  echo "── diagnose: recent events (all namespaces, last 100)"
  kubectl get events -A --sort-by=.lastTimestamp 2>/dev/null | tail -n 100 | tee "${STATE_DIR}/events.txt" || true
  echo "── diagnose: node conditions / pressure"
  kubectl get nodes -o wide 2>/dev/null || true
  kubectl describe nodes 2>/dev/null \
    | grep -A6 -E '^  (Ready|MemoryPressure|DiskPressure|PIDPressure)' \
    | tee "${STATE_DIR}/node-conditions.txt" || true
  kubectl top nodes 2>/dev/null | tee -a "${STATE_DIR}/node-conditions.txt" || true
  for c in "${APP_COMPONENTS[@]}"; do
    echo "── diagnose: ${c} namespace (if any)"
    kubectl -n "${c}" get pods -o wide 2>/dev/null || true
    echo "── diagnose: non-Ready pods in ${c} namespace (describe + tailed logs)"
    while IFS= read -r pod; do
      [ -n "${pod}" ] || continue
      ready="$(kubectl -n "${c}" get pod "${pod}" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
      [ "${ready}" = "True" ] && continue
      echo "--- describe pod/${pod}"
      kubectl -n "${c}" describe pod "${pod}" 2>/dev/null || true
      echo "--- logs pod/${pod} (tail 100)"
      kubectl -n "${c}" logs "pod/${pod}" --tail=100 2>/dev/null || true
    done < <(kubectl -n "${c}" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
    echo "── diagnose: endpoint slices backing ${c} services"
    kubectl -n "${c}" get endpointslice -o wide 2>/dev/null || true
  done
  echo "── diagnose: cloud emulator (ns ${CLOUD_NAMESPACE:-cloud})"
  kubectl -n "${CLOUD_NAMESPACE:-cloud}" get svc,endpointslice,pods -o wide 2>&1 \
    | tee "${STATE_DIR}/cloud-diagnose.txt" || true
  kubectl -n "${CLOUD_SMOKE_NS:-cloud-smoke}" get job,pods -o wide 2>&1 \
    | tee -a "${STATE_DIR}/cloud-diagnose.txt" || true
  echo "── diagnose: EKS substrate (context ${FLOCI_EKS_CONTEXT:-floci-eks})"
  kubectl --context "${FLOCI_EKS_CONTEXT:-floci-eks}" get nodes -o wide 2>&1 \
    | tee "${STATE_DIR}/eks-diagnose.txt" || true
  kubectl --context "${FLOCI_EKS_CONTEXT:-floci-eks}" -n "${EKS_SMOKE_NS:-eks-smoke}" get job,pods -o wide 2>&1 \
    | tee -a "${STATE_DIR}/eks-diagnose.txt" || true
}

echo "== smoke-ci: components=${COMPONENTS[*]} ref=${ref} keep=${KEEP_CLUSTER} boot=${BOOT_CLUSTER} cloud=${CLOUD_ON}"

# kubectl authenticates through `aws eks get-token`, so every mode — including
# `--no-cluster` against an existing substrate — needs the Floci IAM credentials
# and endpoint exported, not only the boot path.
if [ -f ".secrets/eks-admin.env" ]; then
  # shellcheck disable=SC1091
  . ".secrets/eks-admin.env"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
fi
export AWS_ENDPOINT_URL="http://127.0.0.1:${FLOCI_PORT:-4566}"
export AWS_DEFAULT_REGION="${FLOCI_AWS_REGION:-us-east-1}"
export AWS_EC2_METADATA_DISABLED=true

if [ "${BOOT_CLUSTER}" = "1" ]; then
  echo "── make eks-up"
  make eks-up
fi

# Wait for an Application to become Synced (any health). Health is deliberately
# NOT a gate here: stateful components (e.g. Vault) are born sealed/uninitialized
# and only become Healthy *after* their own smoke seeds them (smoke-vault.sh →
# seed-vault.sh). Requiring Healthy first would deadlock their bootstrap, so
# converge on `Synced` first and let the platform gate below assert health.
wait_for_synced() {
  local app="$1" announced=0 deadline now output sync_health status
  echo "── wait for Application/${app} Synced (any health; timeout ${TIMEOUT}s)"
  deadline=$(( $(date +%s) + TIMEOUT ))
  while : ; do
    now="$(date +%s)"
    [ "${now}" -lt "${deadline}" ] || { echo "FAIL: Application/${app} did not become Synced within ${TIMEOUT}s" >&2; diagnose; exit 1; }

    sync_health=""
    if output="$(kubectl get application "${app}" -n argocd --no-headers \
        -o custom-columns=SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null)"; then
      sync_health="${output}"
    elif [ "${announced}" = "0" ]; then
      echo "── waiting for Application/${app} to appear (ApplicationSet controller)..." >&2
      announced=1
    fi

    [ -n "${sync_health}" ] || { sleep "${POLL}"; continue; }

    status="$(printf '%s\n' "${sync_health}" | awk '{print $1}')"
    if [ "${status}" = "Missing" ]; then
      echo "FAIL: Application/${app} sync Missing (source not found)" >&2; diagnose; exit 1
    fi
    if [ "${status}" = "Synced" ]; then
      echo "[OK] Application/${app} is Synced (health: $(printf '%s\n' "${sync_health}" | awk '{print $2}'))"
      return 0
    fi
    sleep "${POLL}"
  done
}

# Platform convergence gate: every catalog Application must reach
# Synced/Healthy. Degraded is tolerated as transient (CRD-shipping apps are born
# Degraded while CRDs establish, argoproj/argo-cd#26346) — the gate is the
# deadline.
wait_for_healthy() {
  local app="$1" c="${2:-}" degraded_announced=0 deadline now output health status health_status
  echo "── wait for Application/${app} Synced/Healthy (timeout ${TIMEOUT}s)"
  deadline=$(( $(date +%s) + TIMEOUT ))
  while : ; do
    now="$(date +%s)"
    [ "${now}" -lt "${deadline}" ] || { echo "FAIL: Application/${app} did not converge to Healthy within ${TIMEOUT}s" >&2; [ -n "${c}" ] && diagnose; exit 1; }

    health=""
    if output="$(kubectl get application "${app}" -n argocd --no-headers \
        -o custom-columns=SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null)"; then
      health="${output}"
    fi
    [ -n "${health}" ] || { sleep "${POLL}"; continue; }
    status="$(printf '%s\n' "${health}" | awk '{print $1}')"
    health_status="$(printf '%s\n' "${health}" | awk '{print $2}')"
    [ "${status}" = "Missing" ] && { echo "FAIL: Application/${app} sync Missing" >&2; [ -n "${c}" ] && diagnose; exit 1; }
    case "${status}/${health_status}" in
      Synced/Healthy) echo "[OK] Application/${app} is Synced/Healthy"; return 0 ;;
      Synced/Degraded)
        if [ "${degraded_announced}" = "0" ]; then
          echo "── Application/${app} Degraded (${health_status}) — possibly transient CRD/operator convergence, waiting for ArgoCD refresh..." >&2
          degraded_announced=1
        fi ;;
    esac
    sleep "${POLL}"
  done
}

# ── boot the platform COMPLETE (real app-of-apps) ───────────────────────────
# `make bootstrap` is the single owner of the catalog wiring: it seeds the
# platform ApplicationSet (argocd/apps-<env>.yaml) and the dedicated Kong
# Application (argocd/kong-<env>.yaml) with GIT_TARGET_BRANCH resolved to the PR
# head, so the children track the ref under test. No git serve is involved: the
# host seeds the objects directly (the runner cannot reach the EKS node's pod
# network). `local` runs no services, so there is no root Application to apply.
echo "── make bootstrap ENV=${ENV:-local} (full platform on the EKS substrate)"
ENV="${ENV:-local}" GIT_TARGET_BRANCH="${ref}" make bootstrap

echo "── waiting for ${#CATALOG[@]} platform Applications to converge: ${CATALOG[*]}"
for c in "${CATALOG[@]}"; do
  wait_for_synced "${c}-${APP_SUFFIX}"
done

# Vault is born sealed: seed/unseal it before the health gate, unconditionally —
# the platform cannot be Healthy without it regardless of which component the
# PR touched. seed-vault.sh is idempotent.
echo "── seed Vault (bootstrap prerequisite for the health gate): make smoke COMPONENT=vault"
make smoke COMPONENT=vault

for c in "${CATALOG[@]}"; do
  wait_for_healthy "${c}-${APP_SUFFIX}" "$c"
done
echo "[OK] full platform converged on the EKS substrate"

# Component-level smokes for the touched components, on the converged platform.
for c in "${APP_COMPONENTS[@]}"; do
  [ "$c" = "vault" ] && continue
  echo "── run smoke: make smoke COMPONENT=${c}"
  make smoke COMPONENT="${c}"
done

# EKS-specific: real Kubernetes API via IAM kubeconfig + ECR push/pull.
echo "── run EKS smoke: make smoke COMPONENT=eks"
make smoke COMPONENT=eks

# Cloud-integration smoke: proves the cluster reaches the emulated cloud
# endpoint and can operate against it (see docs/ci-cd.md).
if [ "${CLOUD_ON}" = "1" ]; then
  echo "── run cloud smoke: make smoke COMPONENT=cloud"
  make smoke COMPONENT=cloud
  echo "[OK] smoke-ci: ${COMPONENTS[*]} smoke passed (ref=${ref}); cloud-integration smoke green"
else
  echo "[OK] smoke-ci: ${COMPONENTS[*]} smoke passed (ref=${ref}); cloud smoke skipped (--no-cloud)"
fi
