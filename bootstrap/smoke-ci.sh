#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-ci.sh — shared cluster-smoke framework for `pr-cluster.yml` (Phase 1).
# Encapsulates the boot → apply → wait → run → diagnose → teardown cycle the
# cluster smoke needs, so each component only adds its own smoke command in
# `bootstrap/smoke-<component>.sh` (dispatched via smoke-target.sh). No tooling
# here is platform: it stands up an ephemeral kind cluster, applies the touched
# component via its ArgoCD Application (smoke-app), waits for convergence,
# runs the smoke, and tears the cluster down. Matches docs/ci-cd.md design:
# selective, real chart/CR, no self-heal disabling, profile `local`.
#
# Usage:
#   bootstrap/smoke-ci.sh <component> <ref> [--keep] [--no-cluster]
#   <component>  name of the component to smoke (maps to bootstrap/smoke-<c>.sh)
#   <ref>        git ref (branch/sha) the smoke Application tracks
#   --keep       do not delete the kind cluster on exit (diagnosis)
#   --no-cluster skip cluster-up/argocd-up (use an existing, bootstrapped cluster)
set -euo pipefail

component="${1:-}"
ref="${2:-}"
KEEP_CLUSTER=0
BOOT_CLUSTER=1
for a in "$@"; do
  case "$a" in
    --keep) KEEP_CLUSTER=1 ;;
    --no-cluster) BOOT_CLUSTER=0 ;;
  esac
done

[ -n "$component" ] || { echo "ERROR: usage: $0 <component> <ref> [--keep] [--no-cluster]" >&2; exit 2; }
[ -n "$ref" ] || { echo "ERROR: <ref> is required (head branch/sha for the smoke Application)" >&2; exit 2; }

STATE_DIR=".generated"
APP_NAME="${component}-smoke"
TIMEOUT="${SMOKE_TIMEOUT:-600}"
POLL="${SMOKE_POLL:-10}"

mkdir -p "${STATE_DIR}"

cleanup() {
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
  echo "── diagnose: Application/${APP_NAME}"
  kubectl get application "${APP_NAME}" -n argocd -o yaml 2>/dev/null | tee "${STATE_DIR}/${APP_NAME}-diagnose.yaml" || true
  echo "── diagnose: ApplicationSet/platform-local-smoke"
  kubectl get applicationset platform-local-smoke -n argocd -o yaml 2>/dev/null | tee "${STATE_DIR}/platform-local-smoke-diagnose.yaml" || true
  echo "── diagnose: app status.conditions"
  kubectl get application "${APP_NAME}" -n argocd -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}' 2>/dev/null || true
  echo "── diagnose: operationState"
  kubectl get application "${APP_NAME}" -n argocd -o jsonpath='{.status.operationState.phase}{" — "}{.status.operationState.message}{"\n"}' 2>/dev/null || true
  echo "── diagnose: pods (all namespaces not Running/Completed)"
  kubectl get pods -A --no-headers 2>/dev/null | grep -vE 'Running|Completed' || true
  echo "── diagnose: cert-manager namespace (if any)"
  kubectl -n cert-manager get pods -o wide 2>/dev/null || true
}

echo "== smoke-ci: component=${component} ref=${ref} keep=${KEEP_CLUSTER} boot=${BOOT_CLUSTER}"

if [ "${BOOT_CLUSTER}" = "1" ]; then
  echo "── make cluster-up"
  make cluster-up
  echo "── make argocd-up"
  make argocd-up
fi

echo "── apply smoke ApplicationSet: make smoke-app COMPONENT=${component} REF=${ref}"
make smoke-app COMPONENT="${component}" REF="${ref}"

echo "── wait for Application/${APP_NAME} Synced+Healthy (timeout ${TIMEOUT}s)"
deadline=$(( $(date +%s) + TIMEOUT ))
announced=0
while : ; do
  now="$(date +%s)"
  [ "${now}" -lt "${deadline}" ] || { echo "FAIL: Application/${APP_NAME} did not converge within ${TIMEOUT}s" >&2; diagnose; exit 1; }

  # The ApplicationSet generated <name>-smoke asynchronously; the Application may
  # not exist for a few seconds after `make smoke-app` — that is normal, keep
  # polling until it appears (the deadline above still fail-closes).
  sync_health=""
  if output="$(kubectl get application "${APP_NAME}" -n argocd --no-headers \
      -o custom-columns=SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null)"; then
    sync_health="${output}"
  elif [ "${announced}" = "0" ]; then
    echo "── waiting for Application/${APP_NAME} to appear (ApplicationSet controller)..." >&2
    announced=1
  fi

  # Not generated yet → keep waiting.
  [ -n "${sync_health}" ] || { sleep "${POLL}"; continue; }

  status="$(printf '%s\n' "${sync_health}" | awk '{print $1}')"
  health="$(printf '%s\n' "${sync_health}" | awk '{print $2}')"

  # 'Missing' app or clear failure → fail fast
  if [ "${status}" = "Missing" ]; then
    echo "FAIL: Application/${APP_NAME} is Missing" >&2; diagnose; exit 1
  fi
  case "${status}/${health}" in
    Synced/Healthy) echo "[OK] Application/${APP_NAME} is Synced/Healthy"; break ;;
    */Degraded | */Missing)
      echo "FAIL: Application/${APP_NAME} ${sync_health}" >&2; diagnose; exit 1 ;;
  esac
  sleep "${POLL}"
done

echo "── run smoke: make smoke COMPONENT=${component}"
make smoke COMPONENT="${component}"

echo "[OK] smoke-ci: ${component} smoke passed (ref=${ref})"
