#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-postgres-app.sh — verify the CNPG databases are ready and usable, that
# WAL archiving reaches object storage, and that both a base backup and a
# point-in-time restore produce the expected data:
#   - postgres-app: backup -> marker A -> WAL archive -> target -> marker C;
#     restore to the target must contain A but not C (PITR).
#   - keycloak-db: backup -> marker A -> marker B -> second backup; restoring
#     the latest backup must contain both markers.
#
# `postgres-app` must also carry the platform extensions (pgvector +
# pg_stat_statements) and logical WAL.
#
# Selective smoke for the postgres-app component; driven by
# `make smoke COMPONENT=postgres-app` (see docs/ci-cd.md). Set
# `SMOKE_CNPG_PITR=0` to skip the PITR round-trip (base restore still runs).
set -euo pipefail

NAMESPACE="${POSTGRES_NAMESPACE:-data}"
TIMEOUT="${SMOKE_TIMEOUT:-600s}"
DEADLINE_SECONDS="${SMOKE_DEADLINE:-900}"
ARCHIVE_TIMEOUT="${SMOKE_CNPG_ARCHIVE_TIMEOUT:-300}"
POLL="${SMOKE_POLL:-5}"
PITR_ENABLED="${SMOKE_CNPG_PITR:-1}"
SUFFIX="$(date +%s)-$$"

PRIMARY=""
USERNAME=""
PASSWORD=""
DATABASE=""
RESTORE_CLUSTER=""
BACKUPS=()

cleanup() {
  if [ -n "$RESTORE_CLUSTER" ]; then
    timeout 120 kubectl -n "$NAMESPACE" delete cluster "$RESTORE_CLUSTER" \
      --ignore-not-found --wait=true >/dev/null 2>&1 || true
    kubectl -n "$NAMESPACE" delete pvc -l "cnpg.io/cluster=${RESTORE_CLUSTER}" \
      --ignore-not-found >/dev/null 2>&1 || true
  fi
  if [ "${#BACKUPS[@]}" -gt 0 ]; then
    for backup in "${BACKUPS[@]}"; do
      kubectl -n "$NAMESPACE" delete backup.postgresql.cnpg.io "$backup" \
        --ignore-not-found >/dev/null 2>&1 || true
    done
  fi
}
trap cleanup EXIT

waiter_deadline() {
  echo $(( $(date +%s) + DEADLINE_SECONDS ))
}

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

wait_continuous_archiving() {
  local cluster="$1"
  echo "── smoke(postgres-app): ${cluster} ContinuousArchiving=True"
  kubectl -n "$NAMESPACE" wait --for=condition=ContinuousArchiving \
    "cluster/${cluster}" --timeout="$TIMEOUT" >/dev/null
}

primary_for() {
  kubectl -n "$NAMESPACE" get pod \
    -l "cnpg.io/cluster=$1,cnpg.io/instanceRole=primary" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

secret_value() {
  kubectl -n "$NAMESPACE" get secret "$1" -o jsonpath="{.data.$2}" | base64 -d
}

psql_in() {
  local pod="$1" user="$2" pass="$3" db="$4" sql="$5"
  kubectl -n "$NAMESPACE" exec "$pod" -- env PGPASSWORD="$pass" \
    psql -h 127.0.0.1 -U "$user" -d "$db" -tAc "$sql"
}

psql_retry() {
  local pod="$1" user="$2" pass="$3" db="$4" sql="$5" attempt out
  for attempt in {1..60}; do
    if out="$(psql_in "$pod" "$user" "$pass" "$db" "$sql" 2>/dev/null)"; then
      printf '%s' "$out"
      return 0
    fi
    sleep 2
  done
  echo "FAIL: query did not succeed against ${pod} (db=${db})" >&2
  return 1
}

db_query() {
  psql_in "$PRIMARY" "$USERNAME" "$PASSWORD" "$DATABASE" "$1"
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

  wait_continuous_archiving "$cluster"

  primary="$(primary_for "$cluster")"
  [ -n "$primary" ] || { echo "FAIL: no primary pod for ${cluster}" >&2; exit 1; }

  PRIMARY="$primary"
  USERNAME="$(secret_value "$secret" username)"
  PASSWORD="$(secret_value "$secret" password)"
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

create_backup() {
  local name="$1" cluster="$2"
  echo "── smoke(postgres-app): Backup ${NAMESPACE}/${name} of ${cluster}"
  kubectl -n "$NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: ${name}
  namespace: ${NAMESPACE}
spec:
  cluster:
    name: ${cluster}
  method: barmanObjectStore
EOF
  BACKUPS+=("$name")
}

wait_backup() {
  local name="$1" cluster="$2" deadline phase error backup_id
  deadline="$(waiter_deadline)"
  while : ; do
    phase="$(kubectl -n "$NAMESPACE" get backup.postgresql.cnpg.io "$name" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    error="$(kubectl -n "$NAMESPACE" get backup.postgresql.cnpg.io "$name" \
      -o jsonpath='{.status.error}' 2>/dev/null || true)"
    case "$phase" in
      completed|Completed)
        [ -z "$error" ] || [ "$error" = "null" ] || {
          echo "FAIL: Backup ${name} completed with error: ${error}" >&2
          kubectl -n "$NAMESPACE" get backup.postgresql.cnpg.io "$name" -o yaml >&2 2>/dev/null || true
          exit 1
        }
        backup_id="$(kubectl -n "$NAMESPACE" get backup.postgresql.cnpg.io "$name" \
          -o jsonpath='{.status.backupId}' 2>/dev/null || true)"
        echo "  ${name}: ${backup_id:-<no backupId>}"
        return 0
        ;;
      failed|Failed)
        echo "FAIL: Backup ${name} ended in ${phase}" >&2
        kubectl -n "$NAMESPACE" get backup.postgresql.cnpg.io "$name" -o yaml >&2 2>/dev/null || true
        exit 1
        ;;
    esac
    [ "$(date +%s)" -lt "$deadline" ] || {
      echo "FAIL: Backup ${name} did not complete (last: ${phase:-<none>})" >&2
      kubectl -n "$NAMESPACE" get backup.postgresql.cnpg.io "$name" -o yaml >&2 2>/dev/null || true
      kubectl -n "$NAMESPACE" logs -l "cnpg.io/cluster=${cluster}" --tail=100 >&2 2>/dev/null || true
      exit 1
    }
    sleep "$POLL"
  done
}

wait_for_wal_archive() {
  local since="$1" deadline archived
  deadline=$(( $(date +%s) + ARCHIVE_TIMEOUT ))
  echo "── smoke(postgres-app): waiting for WAL archive >= ${since}"
  while : ; do
    archived="$(db_query "select case when last_archived_time is not null and last_archived_time >= '${since}'::timestamptz then 'yes' else 'no' end from pg_stat_archiver")"
    [ "$archived" = "yes" ] && return 0
    [ "$(date +%s)" -lt "$deadline" ] || {
      echo "FAIL: WAL segment containing the marker was not archived within ${ARCHIVE_TIMEOUT}s" >&2
      db_query "select last_archived_wal, last_archived_time, last_failed_wal, last_failed_time, failed_count from pg_stat_archiver" >&2 || true
      exit 1
    }
    sleep "$POLL"
  done
}

create_restore_cluster() {
  local name="$1" source="$2" backup="$3" secret="$4" target_time="${5:-}"
  local storage image database owner target_yaml=""
  storage="$(kubectl -n "$NAMESPACE" get cluster "$source" -o jsonpath='{.spec.storage.size}')"
  image="$(kubectl -n "$NAMESPACE" get cluster "$source" -o jsonpath='{.spec.imageName}')"
  database="$(kubectl -n "$NAMESPACE" get cluster "$source" -o jsonpath='{.spec.bootstrap.initdb.database}')"
  owner="$(kubectl -n "$NAMESPACE" get cluster "$source" -o jsonpath='{.spec.bootstrap.initdb.owner}')"
  database="${database:-app}"
  owner="${owner:-$database}"
  [ -n "$storage" ] && [ -n "$image" ] || {
    echo "FAIL: could not read storage/image from Cluster ${source}" >&2
    exit 1
  }
  if [ -n "$target_time" ]; then
    target_yaml="        recoveryTarget:
          targetTime: \"${target_time}\""
  fi

  RESTORE_CLUSTER="$name"
  echo "── smoke(postgres-app): restore Cluster ${NAMESPACE}/${name} from ${backup}${target_time:+ at ${target_time}}"
  kubectl -n "$NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${name}
  namespace: ${NAMESPACE}
spec:
  instances: 1
  imageName: ${image}
  storage:
    size: ${storage}
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: "1"
      memory: 1Gi
  affinity:
    enablePodAntiAffinity: false
  bootstrap:
    recovery:
      backup:
        name: ${backup}
      secret:
        name: ${secret}
      database: "${database}"
      owner: "${owner}"
${target_yaml}
EOF

  kubectl -n "$NAMESPACE" wait --for=condition=Ready "cluster/${name}" --timeout="$TIMEOUT" >/dev/null
  kubectl -n "$NAMESPACE" wait --for=condition=Ready pod \
    -l "cnpg.io/cluster=${name}" --timeout="$TIMEOUT" >/dev/null
}

restore_marker_count() {
  local cluster="$1" user="$2" pass="$3" db="$4" marker="$5" pod
  pod="$(primary_for "$cluster")"
  [ -n "$pod" ] || { echo "FAIL: no primary pod for restore cluster ${cluster}" >&2; exit 1; }
  psql_retry "$pod" "$user" "$pass" "$db" \
    "select count(*) from platform_backup_smoke where marker = '${marker}'"
}

delete_restore_cluster() {
  local name="$1"
  kubectl -n "$NAMESPACE" delete cluster "$name" --wait=true --timeout="$TIMEOUT" >/dev/null
  kubectl -n "$NAMESPACE" delete pvc -l "cnpg.io/cluster=${name}" --ignore-not-found >/dev/null
  RESTORE_CLUSTER=""
}

delete_backup() {
  local name="$1"
  kubectl -n "$NAMESPACE" delete backup.postgresql.cnpg.io "$name" --ignore-not-found >/dev/null
  local remaining=()
  for backup in "${BACKUPS[@]}"; do
    [ "$backup" = "$name" ] || remaining+=("$backup")
  done
  BACKUPS=("${remaining[@]}")
}

reset_smoke_table() {
  db_query "create table if not exists platform_backup_smoke (marker text primary key, created_at timestamptz not null default now())" >/dev/null
}

run_pitr_test() {
  local marker_a="${SUFFIX}-pitr-a"
  local marker_b="${SUFFIX}-pitr-b"
  local marker_c="${SUFFIX}-pitr-c"
  local backup="smoke-pitr-${SUFFIX}"
  local restore="smoke-restore-pitr-${SUFFIX}"
  local marker_b_time target_time count

  if [ "$PITR_ENABLED" != "1" ]; then
    echo "── smoke(postgres-app): PITR round-trip skipped (SMOKE_CNPG_PITR=0)"
    return 0
  fi

  echo "── smoke(postgres-app): PITR round-trip on postgres-app"
  wait_externalsecret cnpg-backup-credentials
  reset_smoke_table
  db_query "insert into platform_backup_smoke(marker) values ('${marker_a}')" >/dev/null

  create_backup "$backup" postgres-app
  wait_backup "$backup" postgres-app

  marker_b_time="$(db_query "insert into platform_backup_smoke(marker) values ('${marker_b}') returning to_char(created_at at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"')")"
  [ -n "$marker_b_time" ] || { echo "FAIL: could not capture marker B timestamp" >&2; exit 1; }
  wait_for_wal_archive "$marker_b_time"

  target_time="$(db_query "select to_char(clock_timestamp() at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"')")"
  [ -n "$target_time" ] || { echo "FAIL: could not capture PITR target time" >&2; exit 1; }
  sleep 1
  db_query "insert into platform_backup_smoke(marker) values ('${marker_c}')" >/dev/null

  create_restore_cluster "$restore" postgres-app "$backup" postgres-app-credentials "$target_time"

  count="$(restore_marker_count "$restore" "$USERNAME" "$PASSWORD" "$DATABASE" "$marker_a")"
  [ "$count" = "1" ] || { echo "FAIL: PITR restore is missing marker A (count=${count})" >&2; exit 1; }
  count="$(restore_marker_count "$restore" "$USERNAME" "$PASSWORD" "$DATABASE" "$marker_b")"
  [ "$count" = "1" ] || { echo "FAIL: PITR restore is missing marker B (count=${count})" >&2; exit 1; }
  count="$(restore_marker_count "$restore" "$USERNAME" "$PASSWORD" "$DATABASE" "$marker_c")"
  [ "$count" = "0" ] || { echo "FAIL: PITR restore unexpectedly contains marker C (count=${count})" >&2; exit 1; }

  delete_restore_cluster "$restore"
  delete_backup "$backup"
  db_query "delete from platform_backup_smoke where marker in ('${marker_a}','${marker_b}','${marker_c}')" >/dev/null
  echo "  PITR: A=1 B=1 C=0 (target ${target_time})"
}

run_latest_restore_test() {
  local marker_a="${SUFFIX}-latest-a"
  local marker_b="${SUFFIX}-latest-b"
  local backup_a="smoke-latest-a-${SUFFIX}"
  local backup_b="smoke-latest-b-${SUFFIX}"
  local restore="smoke-restore-latest-${SUFFIX}"
  local count

  echo "── smoke(postgres-app): latest-backup restore on keycloak-db"
  wait_externalsecret cnpg-backup-credentials
  reset_smoke_table
  db_query "insert into platform_backup_smoke(marker) values ('${marker_a}')" >/dev/null

  create_backup "$backup_a" keycloak-db
  wait_backup "$backup_a" keycloak-db

  db_query "insert into platform_backup_smoke(marker) values ('${marker_b}')" >/dev/null

  create_backup "$backup_b" keycloak-db
  wait_backup "$backup_b" keycloak-db

  create_restore_cluster "$restore" keycloak-db "$backup_b" keycloak-db-credentials

  count="$(restore_marker_count "$restore" "$USERNAME" "$PASSWORD" "$DATABASE" "$marker_a")"
  [ "$count" = "1" ] || { echo "FAIL: latest restore is missing marker A (count=${count})" >&2; exit 1; }
  count="$(restore_marker_count "$restore" "$USERNAME" "$PASSWORD" "$DATABASE" "$marker_b")"
  [ "$count" = "1" ] || { echo "FAIL: latest restore is missing marker B (count=${count})" >&2; exit 1; }

  delete_restore_cluster "$restore"
  delete_backup "$backup_a"
  delete_backup "$backup_b"
  db_query "delete from platform_backup_smoke where marker in ('${marker_a}','${marker_b}')" >/dev/null
  echo "  latest: A=1 B=1"
}

verify_cluster postgres-app postgres-app-credentials app "app@app" "pg_stat_statements,vector" 1
run_pitr_test
verify_cluster keycloak-db keycloak-db-credentials keycloak "keycloak@keycloak"
run_latest_restore_test

echo "[OK] smoke(postgres-app): postgres-app + keycloak-db Ready, WAL archiving green, backups restored"
