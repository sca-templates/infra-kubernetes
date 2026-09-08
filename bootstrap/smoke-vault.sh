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
kubectl -n "$NAMESPACE" wait --for=jsonpath='{.status.phase}'=Running "pod/$POD" --timeout="$TIMEOUT"

echo "── smoke(vault): vault status"
status_json="$(vault_status_json)"
initialized="$(printf '%s' "$status_json" | jq -r '.initialized')"
sealed="$(printf '%s' "$status_json" | jq -r '.sealed')"

if [ "$initialized" != "true" ]; then
  echo "── smoke(vault): Vault not initialized — running idempotent seed (bootstrap/seed-vault.sh)"
  "$(dirname "$0")/seed-vault.sh"
  status_json="$(vault_status_json)"
  initialized="$(printf '%s' "$status_json" | jq -r '.initialized // false')"
  sealed="$(printf '%s' "$status_json" | jq -r '.sealed // empty')"
fi

if [ "$initialized" != "true" ] || [ "$sealed" != "false" ]; then
  echo "FAIL: Vault not healthy — initialized=${initialized}, sealed=${sealed}" >&2
  printf '%s\n' "$status_json" >&2
  exit 1
fi

echo "[OK] smoke(vault): Vault initialized=${initialized} sealed=${sealed}"
