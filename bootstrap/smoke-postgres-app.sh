#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-postgres-app.sh — verify the CNPG databases are ready and usable, that
# WAL archiving reaches object storage, and that both a base backup and a
# point-in-time restore produce the expected data:
#   - postgres-app: backup -> marker A -> WAL archive -> target -> marker C;
#     restore to the target must contain A but not C (PITR).
#   - zitadel-db: backup -> marker A -> marker B -> second backup; restoring
#     the latest backup must contain both markers.
#
# `postgres-app` must also carry the platform extensions (pgvector +
# pg_stat_statements + pgaudit) and logical WAL.
#
# Selective smoke for the postgres-app component; driven by
# `make smoke COMPONENT=postgres-app` (see docs/ci-cd.md). Set
# `SMOKE_CNPG_PITR=0` to skip the PITR round-trip (base restore still runs).
set -euo pipefail

NAMESPACE="${POSTGRES_NAMESPACE:-data}"
CNPG_OPERATOR_NAMESPACE="${CNPG_OPERATOR_NAMESPACE:-cloudnative-pg}"
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
TLS_NAMESPACES=()

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
  if [ "${#TLS_NAMESPACES[@]}" -gt 0 ]; then
    for ns in "${TLS_NAMESPACES[@]}"; do
      kubectl delete namespace "$ns" --ignore-not-found --wait=false >/dev/null 2>&1 || true
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

wait_objectstore() {
  local name="$1"
  echo "── smoke(postgres-app): ObjectStore ${NAMESPACE}/${name} present"
  for attempt in {1..60}; do
    kubectl -n "$NAMESPACE" get objectstore "$name" --no-headers >/dev/null 2>&1 && return 0
    [ "$attempt" -eq 60 ] && {
      echo "FAIL: ObjectStore ${NAMESPACE}/${name} not found" >&2
      exit 1
    }
    sleep "$POLL"
  done
}

dump_continuous_archiving_diagnostics() {
  local cluster="$1" primary user pass
  echo "--- Cluster/${cluster} conditions" >&2
  kubectl -n "$NAMESPACE" get cluster "$cluster" \
    -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}' >&2 || true
  echo "--- Cluster/${cluster} status" >&2
  kubectl -n "$NAMESPACE" get cluster "$cluster" -o yaml >&2 || true
  echo "--- pods for cluster/${cluster}" >&2
  kubectl -n "$NAMESPACE" get pods -l "cnpg.io/cluster=${cluster}" -o wide >&2 || true
  echo "--- backups" >&2
  kubectl -n "$NAMESPACE" get backup.postgresql.cnpg.io -o wide >&2 || true

  primary="$(primary_for "$cluster")"
  if [ -n "$primary" ]; then
    user="$(secret_value "${cluster}-credentials" username 2>/dev/null || true)"
    pass="$(secret_value "${cluster}-credentials" password 2>/dev/null || true)"
    if [ -n "$user" ] && [ -n "$pass" ]; then
      echo "--- pg_stat_archiver on ${primary}" >&2
      psql_in "$primary" "$user" "$pass" postgres \
        "select last_archived_wal, last_archived_time, last_failed_wal, last_failed_time, failed_count from pg_stat_archiver" >&2 || true
      echo "--- archive settings on ${primary}" >&2
      psql_in "$primary" "$user" "$pass" postgres "show archive_mode; show archive_command;" >&2 || true
    fi
  fi

  echo "--- CNPG instance logs (tail 200)" >&2
  kubectl -n "$NAMESPACE" logs -l "cnpg.io/cluster=${cluster}" --all-containers --tail=200 >&2 || true
  echo "--- CNPG operator logs matching archive/backup/S3 (tail 200)" >&2
  kubectl -n "$CNPG_OPERATOR_NAMESPACE" logs deploy/cloudnative-pg --tail=2000 2>&1 \
    | grep -iE 'error|warn|fail|archive|backup|barman|s3|object|wal' \
    | tail -n 200 >&2 || true
  echo "--- CNPG operator logs (tail 200, raw)" >&2
  kubectl -n "$CNPG_OPERATOR_NAMESPACE" logs deploy/cloudnative-pg --tail=200 >&2 || true
}

wait_continuous_archiving() {
  local cluster="$1"
  echo "── smoke(postgres-app): ${cluster} ContinuousArchiving=True"
  if ! kubectl -n "$NAMESPACE" wait --for=condition=ContinuousArchiving \
    "cluster/${cluster}" --timeout="$TIMEOUT" >/dev/null; then
    echo "FAIL: ${NAMESPACE}/${cluster} did not report ContinuousArchiving=True" >&2
    dump_continuous_archiving_diagnostics "$cluster"
    exit 1
  fi
}

primary_for() {
  kubectl -n "$NAMESPACE" get pod \
    -l "cnpg.io/cluster=$1,cnpg.io/instanceRole=primary" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

secret_value() {
  kubectl -n "$NAMESPACE" get secret "$1" -o jsonpath="{.data.$2}" | base64 -d
}

barman_object_for() {
  kubectl -n "$NAMESPACE" get cluster "$1" \
    -o jsonpath='{.spec.plugins[0].parameters.barmanObjectName}'
}

psql_in() {
  local pod="$1" user="$2" pass="$3" db="$4" sql="$5"
  kubectl -n "$NAMESPACE" exec "$pod" -- env PGPASSWORD="$pass" \
    psql -q -h 127.0.0.1 -U "$user" -d "$db" -tAc "$sql"
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

use_cluster_credentials() {
  local cluster="$1" secret="$2" database="$3"
  PRIMARY="$(primary_for "$cluster")"
  USERNAME="$(secret_value "$secret" username)"
  PASSWORD="$(secret_value "$secret" password)"
  DATABASE="$database"
  [ -n "$PRIMARY" ] && [ -n "$USERNAME" ] && [ -n "$PASSWORD" ] || {
    echo "FAIL: no primary or empty credentials for ${cluster}" >&2
    exit 1
  }
}

verify_image_and_qos() {
  local cluster="$1" image qos
  echo "── smoke(postgres-app): ${cluster} standard image and Guaranteed QoS"
  image="$(kubectl -n "$NAMESPACE" get cluster "$cluster" -o jsonpath='{.spec.imageName}')"
  case "$image" in
    *-system-*)
      echo "FAIL: ${cluster} still pins deprecated image ${image}" >&2
      exit 1
      ;;
  esac
  qos="$(kubectl -n "$NAMESPACE" get pod -l "cnpg.io/cluster=${cluster}" \
    -o jsonpath='{.items[0].status.qosClass}')"
  [ "$qos" = "Guaranteed" ] || {
    echo "FAIL: ${cluster} QoS='${qos}', expected Guaranteed" >&2
    exit 1
  }
  echo "  ${cluster}: image=${image}, qos=${qos}"
}

verify_roles() {
  local cluster="$1" secret="$2" database="$3" pod user pass roles bad role
  echo "── smoke(postgres-app): ${cluster} least-privilege roles"
  for role in app-migrator app-rw app-ro vault-admin; do
    wait_externalsecret "${cluster}-${role}"
  done
  pod="$(primary_for "$cluster")"
  user="$(secret_value "$secret" username)"
  pass="$(secret_value "$secret" password)"
  roles="$(psql_retry "$pod" "$user" "$pass" "$database" \
    "select string_agg(rolname, ',' order by rolname) from pg_roles where rolname in ('app_migrator','app_ro','app_rw','vault_admin')")"
  [ "$roles" = "app_migrator,app_ro,app_rw,vault_admin" ] || {
    echo "FAIL: ${cluster} roles='${roles}', expected app_migrator,app_ro,app_rw,vault_admin" >&2
    exit 1
  }
  bad="$(psql_retry "$pod" "$user" "$pass" "$database" \
    "select string_agg(rolname, ',' order by rolname) from pg_roles where rolname in ('app_migrator','app_ro','app_rw','vault_admin') and (rolsuper or rolbypassrls)")"
  [ -z "$bad" ] || {
    echo "FAIL: ${cluster} roles with superuser or bypassrls: ${bad}" >&2
    exit 1
  }
  echo "  ${cluster}: roles=${roles}, no superuser/bypassrls"
}

verify_tls() {
  local cluster="$1" secret="$2" database="$3"
  local ns_ok="smoke-tls-ok-${cluster}-${SUFFIX}" ns_denied="smoke-tls-denied-${cluster}-${SUFFIX}"
  local pod_ok="pg-client-ok-${cluster}-${SUFFIX}" pod_denied="pg-client-denied-${cluster}-${SUFFIX}"
  local image="ghcr.io/cloudnative-pg/postgresql:18.4-standard-trixie"
  local ca user pass result

  echo "── smoke(postgres-app): ${cluster} TLS verify-full and namespace isolation"
  kubectl create namespace "$ns_ok" >/dev/null
  kubectl label namespace "$ns_ok" db-access=true >/dev/null
  kubectl create namespace "$ns_denied" >/dev/null
  TLS_NAMESPACES+=("$ns_ok" "$ns_denied")

  ca="$(kubectl -n "$NAMESPACE" get secret "${cluster}-ca" \
    -o jsonpath='{.data.ca\.crt}' | base64 -d)"
  [ -n "$ca" ] || { echo "FAIL: no ca.crt in ${NAMESPACE}/${cluster}-ca" >&2; exit 1; }
  kubectl -n "$ns_ok" create secret generic "${cluster}-ca" \
    --from-literal="ca.crt=${ca}" >/dev/null
  user="$(secret_value "$secret" username)"
  pass="$(secret_value "$secret" password)"

  kubectl -n "$ns_ok" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_ok}
spec:
  restartPolicy: Never
  containers:
    - name: psql
      image: ${image}
      command: ["/bin/sh", "-c", "sleep 600"]
      volumeMounts:
        - name: ca
          mountPath: /tls
          readOnly: true
  volumes:
    - name: ca
      secret:
        secretName: ${cluster}-ca
        items:
          - key: ca.crt
            path: ca.crt
EOF
  kubectl -n "$ns_denied" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_denied}
spec:
  restartPolicy: Never
  containers:
    - name: psql
      image: ${image}
      command: ["/bin/sh", "-c", "sleep 600"]
EOF
  kubectl -n "$ns_ok" wait --for=condition=Ready "pod/${pod_ok}" --timeout="$TIMEOUT" >/dev/null
  kubectl -n "$ns_denied" wait --for=condition=Ready "pod/${pod_denied}" --timeout="$TIMEOUT" >/dev/null

  result="$(kubectl -n "$ns_ok" exec "$pod_ok" -- env PGPASSWORD="$pass" psql \
    "host=${cluster}-rw.${NAMESPACE}.svc port=5432 dbname=${database} user=${user} sslmode=verify-full sslrootcert=/tls/ca.crt connect_timeout=10" \
    -tAc 'select 1')"
  [ "$result" = "1" ] || {
    echo "FAIL: verify-full connection from labelled namespace returned '${result}'" >&2
    exit 1
  }

  if kubectl -n "$ns_denied" exec "$pod_denied" -- env PGPASSWORD="$pass" psql \
    "host=${cluster}-rw.${NAMESPACE}.svc port=5432 dbname=${database} user=${user} sslmode=require connect_timeout=5" \
    -tAc 'select 1' >/dev/null 2>&1; then
    echo "FAIL: unlabelled namespace reached ${cluster}-rw despite NetworkPolicy" >&2
    exit 1
  fi
  echo "  ${cluster}: verify-full accepted; unlabelled namespace denied"
}

verify_cluster() {
  local cluster="$1" secret="$2" database="$3" expected_identity="$4"
  local expected_extensions="${5:-}" check_wal="${6:-0}"
  local identity wal_level extensions store plugin

  wait_externalsecret "$secret"
  plugin="$(kubectl -n "$NAMESPACE" get cluster "$cluster" \
    -o jsonpath='{.spec.plugins[0].name}')"
  [ "$plugin" = "barman-cloud.cloudnative-pg.io" ] || {
    echo "FAIL: Cluster ${NAMESPACE}/${cluster} plugin='${plugin}', expected barman-cloud.cloudnative-pg.io" >&2
    exit 1
  }
  store="$(barman_object_for "$cluster")"
  [ -n "$store" ] || {
    echo "FAIL: Cluster ${NAMESPACE}/${cluster} has no barman ObjectStore" >&2
    exit 1
  }
  wait_objectstore "$store"

  echo "── smoke(postgres-app): Cluster ${NAMESPACE}/${cluster} Ready"
  kubectl -n "$NAMESPACE" wait --for=condition=Ready "cluster/${cluster}" --timeout="$TIMEOUT" >/dev/null

  echo "── smoke(postgres-app): ${cluster} pods Ready"
  kubectl -n "$NAMESPACE" wait --for=condition=Ready pod \
    -l "cnpg.io/cluster=${cluster}" --timeout="$TIMEOUT" >/dev/null

  wait_continuous_archiving "$cluster"

  use_cluster_credentials "$cluster" "$secret" "$database"

  echo "── smoke(postgres-app): ${cluster} application connection"
  identity="$(db_query "select current_user || '@' || current_database()")"
  [ "$identity" = "$expected_identity" ] || {
    echo "FAIL: unexpected identity '${identity}', expected '${expected_identity}'" >&2
    exit 1
  }

  if [ -n "$expected_extensions" ]; then
    echo "── smoke(postgres-app): ${cluster} extensions ${expected_extensions}"
    extensions="$(db_query "select string_agg(extname, ',' order by extname) from pg_extension where extname in ('vector','pg_stat_statements','pgaudit')")"
    actual_extensions="$(printf '%s\n' "$extensions" | tr ',' '\n' | LC_ALL=C sort | paste -sd, -)"
    wanted_extensions="$(printf '%s\n' "$expected_extensions" | tr ',' '\n' | LC_ALL=C sort | paste -sd, -)"
    [ "$actual_extensions" = "$wanted_extensions" ] || {
      echo "FAIL: expected set ${wanted_extensions}; got '${actual_extensions}'" >&2
      exit 1
    }
    extensions="$actual_extensions"
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
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
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
  local name="$1" source="$2" secret="$3" target_time="${4:-}"
  local storage image database owner barman_object target_yaml=""
  storage="$(kubectl -n "$NAMESPACE" get cluster "$source" -o jsonpath='{.spec.storage.size}')"
  image="$(kubectl -n "$NAMESPACE" get cluster "$source" -o jsonpath='{.spec.imageName}')"
  database="$(kubectl -n "$NAMESPACE" get cluster "$source" -o jsonpath='{.spec.bootstrap.initdb.database}')"
  owner="$(kubectl -n "$NAMESPACE" get cluster "$source" -o jsonpath='{.spec.bootstrap.initdb.owner}')"
  barman_object="$(barman_object_for "$source")"
  database="${database:-app}"
  owner="${owner:-$database}"
  [ -n "$storage" ] && [ -n "$image" ] && [ -n "$barman_object" ] || {
    echo "FAIL: could not read backup configuration from Cluster ${source}" >&2
    exit 1
  }
  scheduling_yaml=""
  if [ "$(kubectl -n "$NAMESPACE" get cluster "$source" -o jsonpath='{.spec.affinity.nodeSelector.workload}' 2>/dev/null)" = "database" ]; then
    scheduling_yaml="    nodeSelector:
      workload: database
    tolerations:
      - key: workload
        operator: Equal
        value: database
        effect: NoSchedule"
  fi
  if [ -n "$target_time" ]; then
    target_yaml="      recoveryTarget:
        targetTime: \"${target_time}\""
  fi

  RESTORE_CLUSTER="$name"
  echo "── smoke(postgres-app): restore Cluster ${NAMESPACE}/${name} from ${source} object store${target_time:+ at ${target_time}}"
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
${scheduling_yaml}
  bootstrap:
    recovery:
      source: barman-cloud
      secret:
        name: ${secret}
      database: "${database}"
      owner: "${owner}"
${target_yaml}
  externalClusters:
  - name: barman-cloud
    plugin:
      name: barman-cloud.cloudnative-pg.io
      parameters:
        barmanObjectName: ${barman_object}
        serverName: ${source}
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
  wait_externalsecret postgres-app-credentials
  use_cluster_credentials postgres-app postgres-app-credentials app
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

  create_restore_cluster "$restore" postgres-app postgres-app-credentials "$target_time"

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
  local count restore_user restore_pass restore_db

  echo "── smoke(postgres-app): latest-backup restore on zitadel-db"
  wait_externalsecret zitadel-db-credentials
  wait_externalsecret cnpg-backup-credentials
  use_cluster_credentials zitadel-db zitadel-db-credentials zitadel
  restore_user="$USERNAME"
  restore_pass="$PASSWORD"
  restore_db="$DATABASE"
  reset_smoke_table
  db_query "insert into platform_backup_smoke(marker) values ('${marker_a}')" >/dev/null

  create_backup "$backup_a" zitadel-db
  wait_backup "$backup_a" zitadel-db

  db_query "insert into platform_backup_smoke(marker) values ('${marker_b}')" >/dev/null

  create_backup "$backup_b" zitadel-db
  wait_backup "$backup_b" zitadel-db

  create_restore_cluster "$restore" zitadel-db zitadel-db-credentials

  count="$(restore_marker_count "$restore" "$restore_user" "$restore_pass" "$restore_db" "$marker_a")"
  [ "$count" = "1" ] || { echo "FAIL: latest restore is missing marker A (count=${count})" >&2; exit 1; }
  count="$(restore_marker_count "$restore" "$restore_user" "$restore_pass" "$restore_db" "$marker_b")"
  [ "$count" = "1" ] || { echo "FAIL: latest restore is missing marker B (count=${count})" >&2; exit 1; }

  delete_restore_cluster "$restore"
  delete_backup "$backup_a"
  delete_backup "$backup_b"
  db_query "delete from platform_backup_smoke where marker in ('${marker_a}','${marker_b}')" >/dev/null
  echo "  latest: A=1 B=1"
}

verify_cluster postgres-app postgres-app-credentials app "app@app" "pgaudit,pg_stat_statements,vector" 1
verify_image_and_qos postgres-app
verify_roles postgres-app postgres-app-credentials app
verify_tls postgres-app postgres-app-credentials app
run_pitr_test
verify_cluster zitadel-db zitadel-db-credentials zitadel "zitadel@zitadel" "pgaudit"
verify_image_and_qos zitadel-db
verify_roles zitadel-db zitadel-db-credentials zitadel
verify_tls zitadel-db zitadel-db-credentials zitadel
run_latest_restore_test

echo "[OK] smoke(postgres-app): postgres-app + zitadel-db Ready, pgaudit, least-privilege roles, Guaranteed QoS, TLS verified, plugin WAL archiving green, backups restored"
