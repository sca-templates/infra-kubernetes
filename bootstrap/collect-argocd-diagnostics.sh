#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# collect-argocd-diagnostics.sh — dump the ArgoCD install state when `make
# argocd-up` fails, so the ephemeral-runner failure carries evidence (pod
# status, describe, events) instead of only the Helm error.
#
# The smoke framework's `diagnose()` runs *after* ArgoCD is up; an `argocd-up`
# failure happens before it, so without this dump there is nothing to inspect.
# Output lands in `.generated/` (uploaded as a CI artifact) and on stdout.
#
# CI/dev tooling only — never a platform component. Read-only and fail-soft.
set -uo pipefail
# NB: no `-e` — every probe must run even after one fails.

state_dir="${STATE_DIR:-.generated}"
mkdir -p "${state_dir}"
out="${state_dir}/argocd-up-diagnose.txt"

{
  echo "── argocd-up diagnose: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "== namespace argocd: pods"
  kubectl -n argocd get pods -o wide 2>&1 || true
  echo
  echo "== namespace argocd: deployments/statefulsets/replicasets"
  kubectl -n argocd get deploy,sts,rs -o wide 2>&1 || true
  echo
  echo "== namespace argocd: jobs (pre-install hooks)"
  kubectl -n argocd get jobs -o wide 2>&1 || true
  echo
  echo "== namespace argocd: non-running pods (describe)"
  while IFS= read -r pod; do
    [ -n "${pod}" ] || continue
    echo "--- describe pod/${pod}"
    kubectl -n argocd describe pod "${pod}" 2>&1 || true
    echo "--- logs pod/${pod} (tail 100)"
    kubectl -n argocd logs "pod/${pod}" --tail=100 --all-containers 2>&1 || true
  done < <(kubectl -n argocd get pods --no-headers 2>/dev/null \
    | awk '$3 != "Running" && $3 != "Completed" {print $1}')
  echo
  echo "== namespace argocd: events"
  kubectl -n argocd get events --sort-by=.lastTimestamp 2>&1 || true
  echo
  echo "== recent events (all namespaces, last 60)"
  kubectl get events -A --sort-by=.lastTimestamp 2>&1 | tail -n 60 || true
  echo
  echo "== nodes"
  kubectl get nodes -o wide 2>&1 || true
} | tee "${out}"
