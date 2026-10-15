#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-ci.sh — shared cluster-smoke framework for `pr-cluster.yml` (Phase 1).
# Encapsulates the boot → apply → wait → run → diagnose → teardown cycle the
# cluster smoke needs, so each component only adds its own smoke command in
# `bootstrap/smoke-<component>.sh` (dispatched via smoke-target.sh). No tooling
# here is platform: it stands up an ephemeral cluster, applies the touched
# component(s) (or the whole platform on the EKS substrate), waits for
# convergence, runs the smoke, and tears the cluster down. Matches docs/ci-cd.md
# design: selective, real chart/CR, no self-heal disabling, profile `local`.
#
# Two substrates (SMOKE_SUBSTRATE / --substrate):
#   - `kind` (default): ephemeral kind cluster, the touched component(s) rendered
#     as `<name>-smoke` via the smoke ApplicationSet. Fast, selective.
#   - `eks`: Floci's emulated EKS (a real k3s node; bootstrap/eks-emulator.sh).
#     Boots the *full* platform through the real app-of-apps (`make bootstrap
#     ENV=local`, `<name>-local`), waits for every catalog Application to
#     converge, and runs the EKS/ECR + cloud integration smokes. The most
#     complete test: EKS integration + a real deployment of the whole catalog.
#
# More than one component can be smoked in a single run: `<component>` is a
# comma-separated list, the cluster is booted once, the cloud emulator is
# brought up once, each component is applied/waited/smoked in turn, the cloud
# smoke runs once, and teardown runs once.
#
# Usage:
#   bootstrap/smoke-ci.sh <component[,component...]> <ref> [--keep] [--no-cluster] [--no-cloud] [--substrate kind|eks] [--full]
#   <component>  component(s) to smoke (maps to bootstrap/smoke-<c>.sh); `cloud`
#                and `eks` are smoke targets with no ArgoCD Application
#   <ref>        git ref (branch/sha) the smoke Application tracks
#   --keep       do not delete the cluster on exit (diagnosis)
#   --no-cluster skip cluster-up/argocd-up (use an existing, bootstrapped cluster)
#   --no-cloud   skip the cloud emulator (Floci) and its cloud-integration smoke
#                (SMOKE_CLOUD=0 does the same; the smoke is on by default)
#   --substrate  `kind` (default) or `eks` (SMOKE_SUBSTRATE does the same)
#   --full       force the whole-platform path (SMOKE_FULL=1); implied by `eks`
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

components_raw="${1:-}"
ref="${2:-}"
KEEP_CLUSTER=0
BOOT_CLUSTER=1
CLOUD_ON=1
SUBSTRATE="${SMOKE_SUBSTRATE:-kind}"
FULL="${SMOKE_FULL:-0}"
if [ -n "${SMOKE_CLOUD:-}" ] && [ "${SMOKE_CLOUD}" = "0" ]; then
  CLOUD_ON=0
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --keep) KEEP_CLUSTER=1 ;;
    --no-cluster) BOOT_CLUSTER=0 ;;
    --no-cloud) CLOUD_ON=0 ;;
    --full) FULL=1 ;;
    --substrate) SUBSTRATE="${2:-}"; shift ;;
    --substrate=*) SUBSTRATE="${1#*=}" ;;
    --*) echo "ERROR: unknown flag '$1'" >&2; exit 2 ;;
  esac
  shift
done

case "${SUBSTRATE}" in
  kind | eks) ;;
  *) echo "ERROR: unknown substrate '${SUBSTRATE}' (known: kind, eks)" >&2; exit 2 ;;
esac
# The EKS substrate is the whole platform by definition (and its cluster is the
# cloud emulator itself, so it cannot run without it).
if [ "${SUBSTRATE}" = "eks" ]; then
  FULL=1
  [ "${CLOUD_ON}" = "1" ] || { echo "ERROR: substrate=eks needs the cloud emulator — drop --no-cloud / SMOKE_CLOUD=0" >&2; exit 2; }
fi

[ -n "$components_raw" ] || { echo "ERROR: usage: $0 <component[,component...]> <ref> [--keep] [--no-cluster] [--no-cloud] [--substrate kind|eks] [--full]" >&2; exit 2; }
[ -n "$ref" ] || { echo "ERROR: <ref> is required (head branch/sha for the smoke Application)" >&2; exit 2; }

# Split the comma-separated list into an array (commas -> spaces, then word
# split); component names never contain whitespace.
COMPONENTS=()
for _c in ${components_raw//,/ }; do
  [ -n "$_c" ] && COMPONENTS+=("$_c")
done
unset _c
[ "${#COMPONENTS[@]}" -gt 0 ] || { echo "ERROR: no components resolved from '${components_raw}'" >&2; exit 2; }

# `cloud` and `eks` are smoke targets, not ArgoCD Applications: they never go
# through smoke-app/wait (there is no Application to converge). Everything else
# is an Application rendered by the smoke ApplicationSet.
APP_COMPONENTS=()
HAS_CLOUD=0
HAS_EKS=0
for c in "${COMPONENTS[@]}"; do
  case "$c" in
    cloud) HAS_CLOUD=1 ;;
    eks) HAS_EKS=1 ;;
    *) APP_COMPONENTS+=("$c") ;;
  esac
done
if [ "${HAS_EKS}" = "1" ] && [ "${SUBSTRATE}" != "eks" ]; then
  echo "ERROR: component=eks needs the EKS substrate — run with --substrate eks / SMOKE_SUBSTRATE=eks" >&2
  exit 2
fi

# Applications rendered on the kind substrate are `<name>-smoke` (the smoke
# ApplicationSet `platform-local-smoke`); on the EKS substrate the full platform
# is applied as `<name>-local` (the real app-of-apps, ApplicationSet
# `platform-local`). The suffix drives every wait/diagnose.
if [ "${SUBSTRATE}" = "eks" ]; then
  APP_SUFFIX="local"; APPSET_NAME="platform-local"
else
  APP_SUFFIX="smoke"; APPSET_NAME="platform-local-smoke"
fi

STATE_DIR=".generated"
TIMEOUT="${SMOKE_TIMEOUT:-900}"
POLL="${SMOKE_POLL:-10}"

mkdir -p "${STATE_DIR}"

cleanup() {
  if [ "${CLOUD_ON}" = "1" ] && [ "${SUBSTRATE}" != "eks" ]; then
    if [ "${KEEP_CLUSTER}" = "1" ]; then
      echo "── smoke-ci: keeping cloud emulator (--keep) — remove with: make cloud-down"
    else
      echo "── smoke-ci: tearing down cloud emulator"
      make cloud-down 2>/dev/null || true
    fi
  fi
  if [ "${KEEP_CLUSTER}" = "1" ]; then
    echo "── smoke-ci: keeping ${SUBSTRATE} cluster (--keep)"
  elif [ "${BOOT_CLUSTER}" = "1" ]; then
    if [ "${SUBSTRATE}" = "eks" ]; then
      echo "── smoke-ci: tearing down EKS substrate"
      make eks-down 2>/dev/null || true
    else
      echo "── smoke-ci: tearing down kind cluster"
      make cluster-down 2>/dev/null || true
    fi
  else
    echo "── smoke-ci: --no-cluster, leaving existing cluster untouched"
  fi
}
trap cleanup EXIT

diagnose() {
  local app c pod ready
  for c in "${COMPONENTS[@]}"; do
    case "$c" in cloud | eks) continue ;; esac
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

echo "== smoke-ci: components=${COMPONENTS[*]} ref=${ref} substrate=${SUBSTRATE} keep=${KEEP_CLUSTER} boot=${BOOT_CLUSTER} cloud=${CLOUD_ON} full=${FULL}"

if [ "${BOOT_CLUSTER}" = "1" ]; then
  if [ "${SUBSTRATE}" = "eks" ]; then
    echo "── make eks-up"
    make eks-up
  else
    echo "── make cluster-up"
    make cluster-up
    echo "── make argocd-up"
    make argocd-up
  fi
fi

# Cloud integration: the emulator is a prerequisite of the cloud smoke and of any
# component that consumes an emulated cloud endpoint. On the kind substrate it
# starts here; on the EKS substrate `make eks-up` already started and published
# it (the emulated EKS cluster *is* the emulator), so it is not restarted.
if [ "${CLOUD_ON}" = "1" ] && [ "${SUBSTRATE}" != "eks" ]; then
  echo "── make cloud-up (emulator provider=${CLOUD_PROVIDER:-aws})"
  make cloud-up
fi

# `cloud` in the list needs the emulator; fail closed if it was disabled.
if [ "${HAS_CLOUD}" = "1" ] && [ "${CLOUD_ON}" != "1" ]; then
  echo "ERROR: component=cloud needs the cloud emulator — drop --no-cloud / SMOKE_CLOUD=0" >&2
  exit 2
fi

# Wait for an Application to become Synced (any health). Health is deliberately
# NOT a gate here: stateful components (e.g. Vault) are born sealed/uninitialized
# and only become Healthy *after* their own smoke seeds them (smoke-vault.sh →
# seed-vault.sh). Requiring Healthy first would deadlock their bootstrap, so
# converge on `Synced` first and let the component smoke assert real readiness;
# the post-smoke gate re-checks Healthy.
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

# Post-smoke convergence gate: the Application must reach Synced/Healthy once
# the component smoke bootstrapped it (e.g. Vault seed). Degraded is tolerated
# as transient (CRD-shipping apps are born Degraded while CRDs establish,
# argoproj/argo-cd#26346) — the gate is the deadline.
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

if [ "${SUBSTRATE}" = "eks" ]; then
  # ── EKS substrate: botar la plataforma COMPLETA (app-of-apps real) ──────────
  echo "── make bootstrap ENV=${ENV:-local} (full platform on EKS)"
  ENV="${ENV:-local}" GIT_TARGET_BRANCH="${ref}" make bootstrap

  # Wait for every catalog Application (infrastructure/<c> → <c>-local). The app
  # list is read from the repo, so a newly-landed component is covered for free.
  CATALOG=()
  for d in infrastructure/*/; do
    [ -d "$d" ] || continue
    c="${d%/}"; c="${c##*/}"
    CATALOG+=("$c")
  done
  echo "── waiting for ${#CATALOG[@]} platform Applications to converge: ${CATALOG[*]}"
  for c in "${CATALOG[@]}"; do
    wait_for_healthy "${c}-${APP_SUFFIX}" "$c"
  done
  echo "[OK] full platform converged on ${SUBSTRATE}"

  # Component-level smokes for the touched components, on the converged platform.
  for c in "${APP_COMPONENTS[@]}"; do
    echo "── run smoke: make smoke COMPONENT=${c}"
    make smoke COMPONENT="${c}"
  done

  # EKS-specific: real Kubernetes API via IAM kubeconfig + ECR push/pull.
  echo "── run EKS smoke: make smoke COMPONENT=eks"
  make smoke COMPONENT=eks
else
  # ── kind substrate: selective smoke of the touched component(s) ─────────────
  for c in "${APP_COMPONENTS[@]}"; do
    echo "── apply smoke ApplicationSet: make smoke-app COMPONENT=${c} REF=${ref}"
    make smoke-app COMPONENT="${c}" REF="${ref}"
    wait_for_synced "${c}-${APP_SUFFIX}"
    echo "── run smoke: make smoke COMPONENT=${c}"
    make smoke COMPONENT="${c}"
  done
fi

# Cloud-integration smoke: proves the cluster reaches the emulated cloud
# endpoint and can operate against it (see docs/ci-cd.md). Runs once per smoke
# run, for every component, unless --no-cloud / SMOKE_CLOUD=0.
if [ "${CLOUD_ON}" = "1" ]; then
  echo "── run cloud smoke: make smoke COMPONENT=cloud"
  make smoke COMPONENT=cloud
fi

# Re-check every Application reached Healthy now that its smoke bootstrapped it.
# On the EKS substrate the platform was already gated Healthy above.
if [ "${SUBSTRATE}" != "eks" ]; then
  for c in "${APP_COMPONENTS[@]}"; do
    wait_for_healthy "${c}-${APP_SUFFIX}" "$c"
  done
fi

if [ "${CLOUD_ON}" = "1" ]; then
  echo "[OK] smoke-ci: ${COMPONENTS[*]} smoke passed (ref=${ref}, substrate=${SUBSTRATE}); cloud-integration smoke green"
else
  echo "[OK] smoke-ci: ${COMPONENTS[*]} smoke passed (ref=${ref}, substrate=${SUBSTRATE}); cloud smoke skipped (--no-cloud)"
fi
