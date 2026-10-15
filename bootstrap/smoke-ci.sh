#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-ci.sh — shared cluster-smoke framework for `pr-cluster.yml` (Phase 1).
# Encapsulates the boot → apply → wait → run → diagnose → teardown cycle the
# cluster smoke needs, so each component only adds its own smoke command in
# `bootstrap/smoke-<component>.sh` (dispatched via smoke-target.sh). No tooling
# here is platform: it stands up an ephemeral kind cluster, applies the touched
# component(s) via the ArgoCD ApplicationSet (smoke-app, which renders every
# catalog component as `<name>-smoke`), waits for convergence, runs the smoke,
# and tears the cluster down. Matches docs/ci-cd.md design: selective, real
# chart/CR, no self-heal disabling, profile `local`.
#
# More than one component can be smoked in a single run: `<component>` is a
# comma-separated list, the cluster is booted once, the cloud emulator is
# brought up once, each component is applied/waited/smoked in turn, the cloud
# smoke runs once, and teardown runs once.
#
# Usage:
#   bootstrap/smoke-ci.sh <component[,component...]> <ref> [--keep] [--no-cluster] [--no-cloud]
#   <component>  component(s) to smoke (maps to bootstrap/smoke-<c>.sh); `cloud`
#                is a smoke target with no ArgoCD Application
#   <ref>        git ref (branch/sha) the smoke Application tracks
#   --keep       do not delete the kind cluster on exit (diagnosis)
#   --no-cluster skip cluster-up/argocd-up (use an existing, bootstrapped cluster)
#   --no-cloud   skip the cloud emulator (Floci) and its cloud-integration smoke
#                (SMOKE_CLOUD=0 does the same; the smoke is on by default)
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
if [ -n "${SMOKE_CLOUD:-}" ] && [ "${SMOKE_CLOUD}" = "0" ]; then
  CLOUD_ON=0
fi
for a in "$@"; do
  case "$a" in
    --keep) KEEP_CLUSTER=1 ;;
    --no-cluster) BOOT_CLUSTER=0 ;;
    --no-cloud) CLOUD_ON=0 ;;
  esac
done

[ -n "$components_raw" ] || { echo "ERROR: usage: $0 <component[,component...]> <ref> [--keep] [--no-cluster] [--no-cloud]" >&2; exit 2; }
[ -n "$ref" ] || { echo "ERROR: <ref> is required (head branch/sha for the smoke Application)" >&2; exit 2; }

# Split the comma-separated list into an array (commas -> spaces, then word
# split); component names never contain whitespace.
COMPONENTS=()
for _c in ${components_raw//,/ }; do
  [ -n "$_c" ] && COMPONENTS+=("$_c")
done
unset _c
[ "${#COMPONENTS[@]}" -gt 0 ] || { echo "ERROR: no components resolved from '${components_raw}'" >&2; exit 2; }

# `cloud` is a smoke target, not an ArgoCD Application: it never goes through
# smoke-app/wait (there is no Application to converge). Everything else is an
# Application (`<name>-smoke`) rendered by the smoke ApplicationSet.
APP_COMPONENTS=()
HAS_CLOUD=0
for c in "${COMPONENTS[@]}"; do
  if [ "$c" = "cloud" ]; then HAS_CLOUD=1; else APP_COMPONENTS+=("$c"); fi
done

STATE_DIR=".generated"
TIMEOUT="${SMOKE_TIMEOUT:-900}"
POLL="${SMOKE_POLL:-10}"

mkdir -p "${STATE_DIR}"

cleanup() {
  if [ "${CLOUD_ON}" = "1" ]; then
    if [ "${KEEP_CLUSTER}" = "1" ]; then
      echo "── smoke-ci: keeping cloud emulator (--keep) — remove with: make cloud-down"
    else
      echo "── smoke-ci: tearing down cloud emulator"
      make cloud-down 2>/dev/null || true
    fi
  fi
  if [ "${KEEP_CLUSTER}" = "1" ]; then
    echo "── smoke-ci: keeping kind cluster (--keep) — remove with: make cluster-down"
  elif [ "${BOOT_CLUSTER}" = "1" ]; then
    echo "── smoke-ci: tearing down kind cluster"
    make cluster-down 2>/dev/null || true
  else
    echo "── smoke-ci: --no-cluster, leaving existing cluster untouched"
  fi
}
trap cleanup EXIT

diagnose() {
  local app c pod ready
  for c in "${COMPONENTS[@]}"; do
    [ "$c" = "cloud" ] && continue
    app="${c}-smoke"
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
  echo "── diagnose: ApplicationSet/platform-local-smoke"
  kubectl get applicationset platform-local-smoke -n argocd -o yaml 2>/dev/null | tee "${STATE_DIR}/platform-local-smoke-diagnose.yaml" || true
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
}

echo "== smoke-ci: components=${COMPONENTS[*]} ref=${ref} keep=${KEEP_CLUSTER} boot=${BOOT_CLUSTER} cloud=${CLOUD_ON}"

if [ "${BOOT_CLUSTER}" = "1" ]; then
  echo "── make cluster-up"
  make cluster-up
  echo "── make argocd-up"
  make argocd-up
fi

# Cloud integration runs on every smoke (docs/ci-cd.md): the emulator is a
# prerequisite of the cloud smoke below and, later, of any component that
# consumes an emulated cloud endpoint. `--no-cloud` / SMOKE_CLOUD=0 opt out.
if [ "${CLOUD_ON}" = "1" ]; then
  echo "── make cloud-up (emulator provider=${CLOUD_PROVIDER:-aws})"
  make cloud-up
fi

# `cloud` in the list needs the emulator; fail closed if it was disabled.
if [ "${HAS_CLOUD}" = "1" ] && [ "${CLOUD_ON}" != "1" ]; then
  echo "ERROR: component=cloud needs the cloud emulator — drop --no-cloud / SMOKE_CLOUD=0" >&2
  exit 2
fi

# Apply + wait + smoke each Application component in turn. `make smoke-app`
# renders the catalog ApplicationSet (every component as `<name>-smoke`), so the
# touched Applications already exist; here we only gate on the ones we smoke.
wait_for_synced() {
  local c="$1" app="$2" announced=0 deadline now output sync_health status
  echo "── wait for Application/${app} Synced (any health; timeout ${TIMEOUT}s)"
  deadline=$(( $(date +%s) + TIMEOUT ))
  while : ; do
    now="$(date +%s)"
    [ "${now}" -lt "${deadline}" ] || { echo "FAIL: Application/${app} did not become Synced within ${TIMEOUT}s" >&2; diagnose; exit 1; }

    # The ApplicationSet generated <name>-smoke asynchronously; the Application
    # may not exist for a few seconds after `make smoke-app` — that is normal,
    # keep polling until it appears (the deadline above still fail-closes).
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

    # Sync `Missing` (source/branch/path/chart not found) is a real failure.
    # Health is deliberately NOT a gate here: stateful components (e.g. Vault)
    # are born sealed/uninitialized and only become Healthy *after* their own
    # smoke seeds them (smoke-vault.sh → seed-vault.sh). Requiring Healthy before
    # the smoke would deadlock that bootstrap, so converge on `Synced` first and
    # let the component smoke assert real readiness; a later phase re-checks Healthy.
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
  local app="$1" degraded_announced=0 deadline now output health status health_status
  echo "── wait for Application/${app} Synced/Healthy post-smoke (timeout ${TIMEOUT}s)"
  deadline=$(( $(date +%s) + TIMEOUT ))
  while : ; do
    now="$(date +%s)"
    [ "${now}" -lt "${deadline}" ] || { echo "FAIL: Application/${app} did not converge to Healthy after smoke within ${TIMEOUT}s" >&2; diagnose; exit 1; }

    health=""
    if output="$(kubectl get application "${app}" -n argocd --no-headers \
        -o custom-columns=SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null)"; then
      health="${output}"
    fi
    [ -n "${health}" ] || { sleep "${POLL}"; continue; }
    status="$(printf '%s\n' "${health}" | awk '{print $1}')"
    health_status="$(printf '%s\n' "${health}" | awk '{print $2}')"
    [ "${status}" = "Missing" ] && { echo "FAIL: Application/${app} sync Missing post-smoke" >&2; diagnose; exit 1; }
    case "${status}/${health_status}" in
      Synced/Healthy) echo "[OK] Application/${app} is Synced/Healthy post-smoke"; return 0 ;;
      Synced/Degraded)
        if [ "${degraded_announced}" = "0" ]; then
          echo "── Application/${app} Degraded (${health_status}) — possibly transient CRD/operator convergence, waiting for ArgoCD refresh..." >&2
          degraded_announced=1
        fi ;;
    esac
    sleep "${POLL}"
  done
}

for c in "${APP_COMPONENTS[@]}"; do
  echo "── apply smoke ApplicationSet: make smoke-app COMPONENT=${c} REF=${ref}"
  make smoke-app COMPONENT="${c}" REF="${ref}"
  wait_for_synced "${c}" "${c}-smoke"
  echo "── run smoke: make smoke COMPONENT=${c}"
  make smoke COMPONENT="${c}"
done

# Cloud-integration smoke: proves the cluster reaches the emulated cloud
# endpoint and can operate against it (see docs/ci-cd.md). Runs once per smoke
# run, for every component, unless --no-cloud / SMOKE_CLOUD=0.
if [ "${CLOUD_ON}" = "1" ]; then
  echo "── run cloud smoke: make smoke COMPONENT=cloud"
  make smoke COMPONENT=cloud
fi

# Re-check every Application reached Healthy now that its smoke bootstrapped it.
for c in "${APP_COMPONENTS[@]}"; do
  wait_for_healthy "${c}-smoke"
done

if [ "${CLOUD_ON}" = "1" ]; then
  echo "[OK] smoke-ci: ${COMPONENTS[*]} smoke passed (ref=${ref}); cloud-integration smoke green"
else
  echo "[OK] smoke-ci: ${COMPONENTS[*]} smoke passed (ref=${ref}); cloud smoke skipped (--no-cloud)"
fi
