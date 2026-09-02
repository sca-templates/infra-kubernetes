#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# seed-vault.sh — Initialize, unseal and seed the local Vault instance.
#   1. Saves init material only under .secrets/
#   2. Configures KV-v2 and Kubernetes auth for External Secrets Operator
#   3. Seeds non-production placeholder values; rotate them before promotion
# Usage: bootstrap/seed-vault.sh
set -euo pipefail

NAMESPACE="${VAULT_NAMESPACE:-vault}"
POD="${VAULT_POD:-vault-0}"
SECRETS_DIR="${SECRETS_DIR:-.secrets}"
INIT_FILE="${SECRETS_DIR}/init-keys.json"
ROOT_FILE="${SECRETS_DIR}/root-token"
POD_WAIT="${VAULT_WAIT_TIMEOUT:-180s}"

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

vault_exec() {
  kubectl -n "$NAMESPACE" exec "$POD" -- env \
    VAULT_ADDR=https://vault.vault.svc.cluster.local:8200 \
    VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
    VAULT_TOKEN="$VAULT_TOKEN" vault "$@"
}

# ArgoCD creates the Vault pod asynchronously after bootstrap, so it may not
# exist yet. Poll until it appears (kubectl wait fails instantly on a missing
# pod), then wait until it is Running.
echo "── Waiting for Vault pod ${NAMESPACE}/${POD} to be created by ArgoCD"
for attempt in {1..180}; do
  if kubectl -n "$NAMESPACE" get pod "$POD" -o name >/dev/null 2>&1; then
    break
  fi
  [ "$attempt" -eq 180 ] && {
    echo "ERROR: pod ${NAMESPACE}/${POD} was never created (ArgoCD sync pending?)" >&2
    exit 1
  }
  sleep 5
done

# The vault-tls Secret is issued by cert-manager (sca-ca chain). On a fresh,
# loaded cluster issuance can lag pod creation, and Vault refuses to serve TLS
# without its cert, so the API below would never answer. Wait for the Secret
# BEFORE the Running probe: the pod mounts vault-tls as a volume, so a missing
# Secret leaves it ContainerCreating for as long as cert-manager takes.
echo "── Waiting for Vault TLS secret ${NAMESPACE}/vault-tls (cert-manager)"
for attempt in {1..120}; do
  if kubectl -n "$NAMESPACE" get secret vault-tls >/dev/null 2>&1; then
    break
  fi
  [ "$attempt" -eq 120 ] && {
    echo "ERROR: Vault TLS secret ${NAMESPACE}/vault-tls was never created by cert-manager" >&2
    kubectl -n "$NAMESPACE" get certificate,secret -o wide >&2 2>/dev/null || true
    kubectl -n "$NAMESPACE" get pod "$POD" -o wide >&2 2>/dev/null || true
    kubectl -n cert-manager get clusterissuer,secret -o wide >&2 2>/dev/null || true
    kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -30 >&2 || true
    exit 1
  }
  sleep 5
done

kubectl -n "$NAMESPACE" wait --for=jsonpath='{.status.phase}'=Running pod/"$POD" --timeout="$POD_WAIT"

# phase=Running only means the container started; the TLS listener may not be up
# yet, so the exec-based vault commands below can hit "connection refused".
# Poll until the API answers. Note: `vault status` exits 2 while sealed, so we
# capture the output (with || true) and test the JSON alone rather than letting
# pipefail turn a sealed Vault into a failure. Budget is generous: on a loaded
# CI node the listener can take minutes to come up.
echo "── Waiting for Vault API to accept connections"
for attempt in {1..150}; do
  status_json="$(kubectl -n "$NAMESPACE" exec "$POD" -- env \
       VAULT_ADDR=https://vault.vault.svc.cluster.local:8200 \
       VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
       vault status -format=json 2>/dev/null || true)"
  if [ -n "${status_json}" ] && printf '%s' "${status_json}" | jq -e 'has("sealed")' >/dev/null 2>&1; then
    echo "  Vault API is up (sealed: $(printf '%s' "${status_json}" | jq -r '.sealed'))"
    break
  fi
  [ "$attempt" -eq 150 ] && {
    echo "ERROR: Vault API did not come up in time" >&2
    echo "  last status output: ${status_json:-<empty>}" >&2
    kubectl -n "$NAMESPACE" get pod "$POD" -o wide >&2 2>/dev/null || true
    kubectl -n "$NAMESPACE" describe pod "$POD" | tail -40 >&2 2>/dev/null || true
    kubectl -n "$NAMESPACE" logs "$POD" --tail=40 >&2 2>/dev/null || true
    exit 1
  }
  sleep 2
done

if [ ! -s "$INIT_FILE" ]; then
  echo "── Initializing Vault"
  kubectl -n "$NAMESPACE" exec "$POD" -- env \
    VAULT_ADDR=https://vault.vault.svc.cluster.local:8200 \
    VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
    vault operator init -key-shares=1 -key-threshold=1 -format=json > "$INIT_FILE"
  chmod 600 "$INIT_FILE"
fi

UNSEAL_KEY="$(jq -r '.unseal_keys_b64[0]' "$INIT_FILE")"
ROOT_TOKEN="$(jq -r '.root_token' "$INIT_FILE")"
[ "$UNSEAL_KEY" != "null" ] && [ "$ROOT_TOKEN" != "null" ] || {
  echo "ERROR: invalid Vault init material in ${INIT_FILE}"
  exit 1
}
printf '%s\n' "$ROOT_TOKEN" > "$ROOT_FILE"
chmod 600 "$ROOT_FILE"
export VAULT_TOKEN="$ROOT_TOKEN"

if ! vault_exec status -format=json 2>/dev/null | jq -e '.sealed == false' >/dev/null; then
  echo "── Unsealing Vault"
  vault_exec operator unseal "$UNSEAL_KEY" >/dev/null
fi

for attempt in {1..60}; do
  if vault_exec status -format=json 2>/dev/null | jq -e '.sealed == false and .initialized == true' >/dev/null; then
    break
  fi
  [ "$attempt" -eq 60 ] && { echo "ERROR: Vault did not become unsealed"; exit 1; }
  sleep 2
done

if ! vault_exec secrets list -format=json | jq -e 'has("secret/")' >/dev/null; then
  echo "── Enabling KV-v2"
  vault_exec secrets enable -path=secret kv-v2 >/dev/null
fi

if ! vault_exec auth list -format=json | jq -e 'has("kubernetes/")' >/dev/null; then
  echo "── Enabling Kubernetes auth"
  vault_exec auth enable kubernetes >/dev/null
fi

echo "── Configuring Kubernetes auth"
kubectl -n "$NAMESPACE" exec "$POD" -- env \
  VAULT_ADDR=https://vault.vault.svc.cluster.local:8200 \
  VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
  VAULT_TOKEN="$VAULT_TOKEN" sh -c 'vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host=https://kubernetes.default.svc:443 \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt' >/dev/null

kubectl -n "$NAMESPACE" exec -i "$POD" -- env \
  VAULT_ADDR=https://vault.vault.svc.cluster.local:8200 \
  VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
  VAULT_TOKEN="$VAULT_TOKEN" vault policy write external-secrets - >/dev/null <<'POLICY'
path "secret/data/*" {
  capabilities = ["read"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
POLICY

vault_exec write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=1h >/dev/null

echo "── Seeding local platform values"
vault_exec kv put secret/keycloak/admin username=admin password="$(openssl rand -hex 24)" >/dev/null
vault_exec kv put secret/keycloak/db username=keycloak password="$(openssl rand -hex 24)" >/dev/null
vault_exec kv put secret/postgres-app/superuser username=postgres password="$(openssl rand -hex 24)" >/dev/null
vault_exec kv put secret/kafka/scram-admin username=admin password="$(openssl rand -hex 24)" >/dev/null
vault_exec kv put secret/kafka/connect username=connect password="$(openssl rand -hex 24)" >/dev/null
vault_exec kv put secret/redis/password password="$(openssl rand -hex 24)" >/dev/null
vault_exec kv put secret/grafana/admin username=admin password="$(openssl rand -hex 24)" >/dev/null
vault_exec kv put secret/unleash/admin username=admin password="$(openssl rand -hex 24)" >/dev/null
vault_exec kv put secret/unleash/db username=unleash password="$(openssl rand -hex 24)" >/dev/null
vault_exec kv put secret/minio/root username=minioadmin password="$(openssl rand -hex 24)" >/dev/null
vault_exec kv put secret/velero/credentials access_key=minioadmin secret_key="$(openssl rand -hex 24)" >/dev/null

# Alertmanager config seed only runs once its source lands (Phase 14); until
# then it is skipped so the script stays idempotent and phase-agnostic.
ALERTMANAGER_CONFIG_SRC="infrastructure/kube-prometheus-stack/alertmanager.config.example.yaml"
if [ -f "$ALERTMANAGER_CONFIG_SRC" ]; then
  vault_exec kv put secret/platform/alertmanager config="$(cat "$ALERTMANAGER_CONFIG_SRC")" >/dev/null
else
  echo "  (skipped) Alertmanager seed: ${ALERTMANAGER_CONFIG_SRC} arrives in Phase 14"
fi

echo "Vault initialized, unsealed and seeded. Init material remains in ${SECRETS_DIR}."