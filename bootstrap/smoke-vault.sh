#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-vault.sh — verify the deployed Vault is operational: initialized and
# unsealed, serving TLS via the cert-manager-issued vault-tls secret, with the
# sca-ca ClusterIssuer Ready. If Vault is not yet initialized (as on a fresh
# cluster), it runs the (idempotent) bootstrap/seed-vault.sh first, then
# re-verifies. Selective smoke for the vault component; driven by
# `make smoke COMPONENT=vault` (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${VAULT_NAMESPACE:-vault}"
POD="${VAULT_POD:-vault-0}"
TIMEOUT="${SMOKE_TIMEOUT:-120s}"
SNAPSHOT_TIMEOUT="${SMOKE_SNAPSHOT_TIMEOUT:-300s}"
SNAPSHOT_JOB="vault-raft-snapshot-smoke"

VAULT_ADDR="https://vault.vault.svc.cluster.local:8200"
VAULT_CACERT="/vault/userconfig/vault-tls/ca.crt"

vault_status_json() {
  kubectl -n "$NAMESPACE" exec "$POD" -- env \
    VAULT_ADDR="$VAULT_ADDR" \
    VAULT_CACERT="$VAULT_CACERT" \
    vault status -format=json 2>/dev/null || true
}

echo "── smoke(vault): sca-ca ClusterIssuer Ready (cert-manager dependency)"
kubectl wait --for=condition=Ready clusterissuer/sca-ca --timeout="$TIMEOUT" >/dev/null

echo "── smoke(vault): TLS secret ${NAMESPACE}/${NAMESPACE}-tls issued by cert-manager"
for attempt in {1..60}; do
  if kubectl -n "$NAMESPACE" get secret vault-tls >/dev/null 2>&1; then
    break
  fi
  [ "$attempt" -eq 60 ] && {
    echo "FAIL: TLS secret ${NAMESPACE}/vault-tls was never issued by cert-manager" >&2
    kubectl -n "$NAMESPACE" get certificate,secret >&2 2>/dev/null || true
    exit 1
  }
  sleep 2
done

echo "── smoke(vault): pod ${NAMESPACE}/${POD} Running"
for attempt in {1..60}; do
  if kubectl -n "$NAMESPACE" get pod "$POD" >/dev/null 2>&1; then
    break
  fi
  [ "$attempt" -eq 60 ] && {
    echo "FAIL: pod ${NAMESPACE}/${POD} was never created (StatefulSet not converging)" >&2
    kubectl -n "$NAMESPACE" get statefulset -o wide >&2 2>/dev/null || true
    exit 1
  }
  sleep 2
done
kubectl -n "$NAMESPACE" wait --for=jsonpath='{.status.phase}'=Running "pod/$POD" --timeout="$TIMEOUT"

echo "── smoke(vault): vault status"
status_json="$(vault_status_json)"
initialized="$(printf '%s' "$status_json" | jq -r '.initialized')"
sealed="$(printf '%s' "$status_json" | jq -r '.sealed')"

if [ "$initialized" != "true" ]; then
  echo "── smoke(vault): Vault not initialized — running idempotent seed (bootstrap/seed-vault.sh)"
  "$(dirname "$0")/seed-vault.sh"
  status_json="$(vault_status_json)"
  initialized="$(printf '%s' "$status_json" | jq -r '.initialized')"
  sealed="$(printf '%s' "$status_json" | jq -r '.sealed')"
fi

if [ "$initialized" != "true" ] || [ "$sealed" != "false" ]; then
  echo "FAIL: Vault not healthy — initialized=${initialized}, sealed=${sealed}" >&2
  printf '%s\n' "$status_json" >&2
  exit 1
fi

echo "[OK] smoke(vault): Vault initialized=${initialized} sealed=${sealed}"

echo "── smoke(vault): raft snapshot CronJob and S3 credentials"
for attempt in {1..60}; do
  if kubectl -n "$NAMESPACE" get serviceaccount vault-snapshot >/dev/null 2>&1 \
    && kubectl -n "$NAMESPACE" get cronjob vault-raft-snapshot >/dev/null 2>&1 \
    && kubectl -n "$NAMESPACE" get externalsecret vault-snapshot-credentials >/dev/null 2>&1; then
    break
  fi
  [ "$attempt" -eq 60 ] && {
    echo "FAIL: Vault snapshot resources are not ready (vault-backup Application not synced?)" >&2
    kubectl -n "$NAMESPACE" get serviceaccount,cronjob,externalsecret,secret 2>&1 | grep -E 'vault-snapshot|vault-raft|NAME' >&2 || true
    exit 1
  }
  sleep 2
done
kubectl -n "$NAMESPACE" annotate externalsecret vault-snapshot-credentials \
  force-sync="$(date +%s)" --overwrite >/dev/null 2>&1 || true
kubectl -n "$NAMESPACE" wait --for=condition=Ready externalsecret/vault-snapshot-credentials --timeout="$SNAPSHOT_TIMEOUT" >/dev/null

kubectl -n "$NAMESPACE" delete job "$SNAPSHOT_JOB" --ignore-not-found >/dev/null
kubectl -n "$NAMESPACE" create job --from=cronjob/vault-raft-snapshot "$SNAPSHOT_JOB" >/dev/null

if ! kubectl -n "$NAMESPACE" wait --for=condition=complete "job/$SNAPSHOT_JOB" --timeout="$SNAPSHOT_TIMEOUT" >/dev/null; then
  echo "FAIL: Vault raft snapshot job did not complete" >&2
  kubectl -n "$NAMESPACE" describe "job/$SNAPSHOT_JOB" >&2 2>/dev/null || true
  kubectl -n "$NAMESPACE" logs "job/$SNAPSHOT_JOB" --all-containers=true >&2 2>/dev/null || true
  exit 1
fi

snapshot_logs="$(kubectl -n "$NAMESPACE" logs "job/$SNAPSHOT_JOB" --all-containers=true 2>/dev/null || true)"
if ! grep -q 'VAULT_SNAPSHOT_OK' <<<"$snapshot_logs"; then
  echo "FAIL: Vault raft snapshot was not created/inspected" >&2
  printf '%s\n' "$snapshot_logs" >&2
  exit 1
fi
if ! grep -q 'VAULT_SNAPSHOT_UPLOADED' <<<"$snapshot_logs"; then
  echo "FAIL: Vault raft snapshot was not uploaded to object storage" >&2
  printf '%s\n' "$snapshot_logs" >&2
  exit 1
fi

echo "[OK] smoke(vault): raft snapshot/upload completed"
if [ "${SMOKE_KEEP_VAULT_JOB:-0}" != "1" ]; then
  kubectl -n "$NAMESPACE" delete job "$SNAPSHOT_JOB" --ignore-not-found >/dev/null
fi
