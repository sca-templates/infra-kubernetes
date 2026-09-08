#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-external-secrets.sh — verify External Secrets projects Vault KV into a
# native Kubernetes Secret: the ClusterSecretStore vault is Ready, a throwaway
# ExternalSecret pulls a seeded path (secret/keycloak/admin) and reaches
# condition Ready/reason SecretSynced, and the projected Secret holds the
# expected data. Vault is the dependency: this smoke runs bootstrap/smoke-vault
# first (idempotent) so a fresh cluster is initialized+seeded before the store
# can authenticate. Selective smoke for the external-secrets component; driven
# by `make smoke COMPONENT=external-secrets` (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${EXTERNAL_SECRETS_NS:-external-secrets}"
SCRATCH_NS="external-secrets-smoke"
TIMEOUT="${SMOKE_TIMEOUT:-120s}"
CSS_TIMEOUT="${ESO_CSS_TIMEOUT:-300}"
ES_TIMEOUT="${ESO_ES_TIMEOUT:-300}"
POLL="${ESO_POLL:-5}"

# The smoke cluster's ArgoCD deploys the whole appset (cert-manager, vault,
# external-secrets) via the app-of-apps; Vault is created but unsealed until
# its own smoke/seed runs. Reuse the vault smoke to get it initialized, unsealed
# and seeded idempotently before the store can authenticate.
echo "── smoke(external-secrets): ensuring Vault is up and seeded (dependency)"
"$(dirname "$0")/smoke-vault.sh"

cleanup() {
  kubectl delete namespace "$SCRATCH_NS" --ignore-not-found 2>/dev/null || true
}
trap cleanup EXIT

echo "── smoke(external-secrets): ClusterSecretStore vault Ready"
css_ready() {
  [ "$(kubectl get clustersecretstore vault -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)" = "True" ]
}
for attempt in $(seq 1 "$CSS_TIMEOUT"); do
  css_ready && { echo "  ClusterSecretStore vault Ready (attempt ${attempt})"; break; }
  [ "$attempt" -eq "$CSS_TIMEOUT" ] && {
    echo "FAIL: ClusterSecretStore vault never became Ready" >&2
    kubectl get clustersecretstore vault -o yaml >&2 2>/dev/null || true
    exit 1
  }
  sleep "$POLL"
done

echo "── smoke(external-secrets): projecting a KV secret via a throwaway ExternalSecret"
kubectl create namespace "$SCRATCH_NS" >/dev/null
kubectl -n "$SCRATCH_NS" apply -f - <<'EOF'
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: smoke-es
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: smoke-secret
  data:
    - secretKey: username
      remoteRef:
        key: secret/keycloak/admin
        property: username
    - secretKey: password
      remoteRef:
        key: secret/keycloak/admin
        property: password
EOF

es_synced() {
  kubectl -n "$SCRATCH_NS" get externalsecret smoke-es -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || true
}
echo "── smoke(external-secrets): waiting for ExternalSecret SecretSynced"
for attempt in $(seq 1 "$ES_TIMEOUT"); do
  reason="$(es_synced)"
  if [ "$reason" = "SecretSynced" ]; then
    echo "  ExternalSecret smoke-es SecretSynced (attempt ${attempt})"
    break
  fi
  [ "$attempt" -eq "$ES_TIMEOUT" ] && {
    echo "FAIL: ExternalSecret smoke-es never reached SecretSynced (last reason: ${reason:-<none>})" >&2
    kubectl -n "$SCRATCH_NS" get externalsecret smoke-es -o yaml >&2 2>/dev/null || true
    kubectl -n "$SCRATCH_NS" get secret smoke-secret >&2 2>/dev/null || true
    exit 1
  }
  sleep "$POLL"
done

echo "── smoke(external-secrets): verifying the projected Secret data"
username="$(kubectl -n "$SCRATCH_NS" get secret smoke-secret -o jsonpath='{.data.username}' | base64 -d)"
[ "$username" = "admin" ] || {
  echo "FAIL: projected Secret data mismatch (username='${username}', expected 'admin')" >&2
  exit 1
}

echo "[OK] smoke(external-secrets): ClusterSecretStore vault Ready + ExternalSecret SecretSynced (username=${username})"