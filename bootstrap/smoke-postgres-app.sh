#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-postgres-app.sh — verify the CNPG databases are ready and usable: both
# ExternalSecrets projected the Vault credentials, the `Cluster` resources
# report Ready, their pods are Ready, and a query through each projected
# application user works. `postgres-app` must also carry the platform
# extensions (pgvector + pg_stat_statements) and logical WAL.
#
# Selective smoke for the postgres-app component; driven by
# `make smoke COMPONENT=postgres-app` (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${POSTGRES_NAMESPACE:-data}"
TIMEOUT="${SMOKE_TIMEOUT:-600s}"

PRIMARY=""
USERNAME=""
PASSWORD=""
DATABASE=""

wait_externalsecret() {
  local name="$1" reason=""
  echo "── smoke(postgres-app): ExternalSecret ${NAMESPACE}/${name} SecretSynced"
  for attempt in {1..120}; do
    reason="$(kubectl -n "$NAMESPACE" get externalsecret "$name" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || true)"
    [ "$reason" = "SecretSynced" ] && return 0
    [ "$attempt" -eq 120 ] && {
      echo "FAIL: ExternalSecret ${NAMESPACE}/${name} never reached SecretSynced (last: ${reason:-<none>})" >&2
      kubectl -n "$NAMESPACE" get externalsecret "$name" -o yaml >&2 2>/dev/null || true
      exit 1
    }
    sleep 5
  done
}

db_query() {
  kubectl -n "$NAMESPACE" exec "$PRIMARY" -- env PGPASSWORD="$PASSWORD" \
    psql -h 127.0.0.1 -U "$USERNAME" -d "$DATABASE" -tAc "$1"
}

verify_cluster() {
  local cluster="$1" secret="$2" database="$3" expected_identity="$4"
  local expected_extensions="${5:-}" check_wal="${6:-0}"
  local primary identity wal_level extensions

  wait_externalsecret "$secret"

  echo "── smoke(postgres-app): Cluster ${NAMESPACE}/${cluster} Ready"
  kubectl -n "$NAMESPACE" wait --for=condition=Ready "cluster/${cluster}" --timeout="$TIMEOUT" >/dev/null

  echo "── smoke(postgres-app): ${cluster} pods Ready"
  kubectl -n "$NAMESPACE" wait --for=condition=Ready pod \
    -l "cnpg.io/cluster=${cluster}" --timeout="$TIMEOUT" >/dev/null

  primary="$(
    kubectl -n "$NAMESPACE" get pod \
      -l "cnpg.io/cluster=${cluster},cnpg.io/instanceRole=primary" \
      -o jsonpath='{.items[0].metadata.name}'
  )"
  [ -n "$primary" ] || { echo "FAIL: no primary pod for ${cluster}" >&2; exit 1; }

  PRIMARY="$primary"
  USERNAME="$(kubectl -n "$NAMESPACE" get secret "$secret" -o jsonpath='{.data.username}' | base64 -d)"
  PASSWORD="$(kubectl -n "$NAMESPACE" get secret "$secret" -o jsonpath='{.data.password}' | base64 -d)"
  DATABASE="$database"
  [ -n "$USERNAME" ] && [ -n "$PASSWORD" ] || { echo "FAIL: projected credentials are empty" >&2; exit 1; }

  echo "── smoke(postgres-app): ${cluster} application connection"
  identity="$(db_query "select current_user || '@' || current_database()")"
  [ "$identity" = "$expected_identity" ] || {
    echo "FAIL: unexpected identity '${identity}', expected '${expected_identity}'" >&2
    exit 1
  }

  if [ -n "$expected_extensions" ]; then
    echo "── smoke(postgres-app): ${cluster} extensions ${expected_extensions}"
    extensions="$(db_query "select string_agg(extname, ',' order by extname) from pg_extension where extname in ('vector','pg_stat_statements')")"
    [ "$extensions" = "$expected_extensions" ] || {
      echo "FAIL: expected ${expected_extensions}; got '${extensions}'" >&2
      exit 1
    }
  fi

  if [ "$check_wal" = "1" ]; then
    wal_level="$(db_query 'show wal_level')"
    [ "$wal_level" = "logical" ] || {
      echo "FAIL: wal_level='${wal_level}', expected logical" >&2
      exit 1
    }
  fi

  echo "  ${cluster}: ${identity}${expected_extensions:+, extensions=${extensions}}${check_wal:+${wal_level:+, wal_level=${wal_level}}}"
}

verify_cluster postgres-app postgres-app-credentials app "app@app" "pg_stat_statements,vector" 1
verify_cluster keycloak-db keycloak-db-credentials keycloak "keycloak@keycloak"

echo "[OK] smoke(postgres-app): postgres-app + keycloak-db Ready"
