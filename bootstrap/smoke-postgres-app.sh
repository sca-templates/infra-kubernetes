#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-postgres-app.sh — verify the CNPG application database is ready and
# usable: the ExternalSecret projected the Vault credentials, the
# `Cluster postgres-app` reports Ready, its pod is Ready, and a query through
# the projected application user works. The app database must also carry the
# platform extensions (pgvector + pg_stat_statements) and logical WAL.
#
# Phase 10 also ships `keycloak-db`; its checks are added in the same phase's
# database commit. Selective smoke for the postgres-app component; driven by
# `make smoke COMPONENT=postgres-app` (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${POSTGRES_NAMESPACE:-data}"
CLUSTER="${POSTGRES_CLUSTER:-postgres-app}"
SECRET="${POSTGRES_CREDENTIALS_SECRET:-postgres-app-credentials}"
TIMEOUT="${SMOKE_TIMEOUT:-600s}"

echo "── smoke(postgres-app): ExternalSecret ${NAMESPACE}/${SECRET%-credentials} SecretSynced"
es_name="${SECRET%-credentials}"
reason=""
for attempt in {1..120}; do
  reason="$(kubectl -n "$NAMESPACE" get externalsecret "$es_name" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || true)"
  [ "$reason" = "SecretSynced" ] && break
  [ "$attempt" -eq 120 ] && {
    echo "FAIL: ExternalSecret ${NAMESPACE}/${es_name} never reached SecretSynced (last: ${reason:-<none>})" >&2
    kubectl -n "$NAMESPACE" get externalsecret "$es_name" -o yaml >&2 2>/dev/null || true
    exit 1
  }
  sleep 5
done
echo "  ExternalSecret ${es_name} → SecretSynced"

echo "── smoke(postgres-app): Cluster ${NAMESPACE}/${CLUSTER} Ready"
kubectl -n "$NAMESPACE" wait --for=condition=Ready "cluster/${CLUSTER}" --timeout="$TIMEOUT" >/dev/null

echo "── smoke(postgres-app): ${CLUSTER} pods Ready"
kubectl -n "$NAMESPACE" wait --for=condition=Ready pod \
  -l "cnpg.io/cluster=${CLUSTER}" --timeout="$TIMEOUT" >/dev/null

primary="$(
  kubectl -n "$NAMESPACE" get pod \
    -l "cnpg.io/cluster=${CLUSTER},cnpg.io/instanceRole=primary" \
    -o jsonpath='{.items[0].metadata.name}'
)"
[ -n "$primary" ] || { echo "FAIL: no primary pod for ${CLUSTER}" >&2; exit 1; }

username="$(kubectl -n "$NAMESPACE" get secret "$SECRET" -o jsonpath='{.data.username}' | base64 -d)"
password="$(kubectl -n "$NAMESPACE" get secret "$SECRET" -o jsonpath='{.data.password}' | base64 -d)"
[ -n "$username" ] && [ -n "$password" ] || { echo "FAIL: projected credentials are empty" >&2; exit 1; }

psql() {
  kubectl -n "$NAMESPACE" exec "$primary" -- env PGPASSWORD="$password" \
    psql -h 127.0.0.1 -U "$username" -d app -tAc "$1"
}

echo "── smoke(postgres-app): application connection + logical WAL"
identity="$(psql "select current_user || '@' || current_database()")"
[ "$identity" = "app@app" ] || { echo "FAIL: unexpected identity '${identity}'" >&2; exit 1; }
wal_level="$(psql 'show wal_level')"
[ "$wal_level" = "logical" ] || { echo "FAIL: wal_level='${wal_level}', expected logical" >&2; exit 1; }

echo "── smoke(postgres-app): extensions vector + pg_stat_statements"
extensions="$(psql "select string_agg(extname, ',' order by extname) from pg_extension where extname in ('vector','pg_stat_statements')")"
[ "$extensions" = "pg_stat_statements,vector" ] || {
  echo "FAIL: expected pg_stat_statements,vector; got '${extensions}'" >&2
  exit 1
}

echo "[OK] smoke(postgres-app): ${CLUSTER} Ready, ${identity}, wal_level=${wal_level}, extensions=${extensions}"
