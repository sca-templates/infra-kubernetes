#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-velero.sh — verify Velero is operational and can restore what it backs
# up: the server is Ready, the default BackupStorageLocation is Available, the
# `velero-critical-namespaces` schedule exists, and a scratch namespace with a
# ConfigMap survives a full Backup -> delete -> Restore round-trip.
#
# Selective smoke for the velero component; driven by
# `make smoke COMPONENT=velero` (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${VELERO_NAMESPACE:-velero}"
TIMEOUT="${SMOKE_TIMEOUT:-600s}"
DEADLINE_SECONDS="${SMOKE_DEADLINE:-900}"
POLL="${SMOKE_POLL:-5}"
SUFFIX="$(date +%s)-$$"
SMOKE_NS="velero-smoke-${SUFFIX}"
BACKUP="velero-smoke-${SUFFIX}"
RESTORE="velero-smoke-${SUFFIX}"
MARKER="restore-ok-${SUFFIX}"

cleanup() {
  kubectl -n "$NAMESPACE" delete restore.velero.io "$RESTORE" \
    --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" delete backup.velero.io "$BACKUP" \
    --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete namespace "$SMOKE_NS" --wait=false --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_backup() {
  local deadline=$(( $(date +%s) + DEADLINE_SECONDS )) phase errors
  while : ; do
    phase="$(kubectl -n "$NAMESPACE" get backup.velero.io "$BACKUP" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    errors="$(kubectl -n "$NAMESPACE" get backup.velero.io "$BACKUP" \
      -o jsonpath='{.status.errors}' 2>/dev/null || true)"
    case "$phase" in
      Completed)
        [ "${errors:-0}" = "0" ] || {
          echo "FAIL: Backup ${BACKUP} completed with ${errors} error(s)" >&2
          kubectl -n "$NAMESPACE" describe backup.velero.io "$BACKUP" >&2 2>/dev/null || true
          exit 1
        }
        return 0
        ;;
      Failed|PartiallyFailed)
        echo "FAIL: Backup ${BACKUP} ended in ${phase} (errors: ${errors:-unknown})" >&2
        kubectl -n "$NAMESPACE" describe backup.velero.io "$BACKUP" >&2 2>/dev/null || true
        exit 1
        ;;
    esac
    [ "$(date +%s)" -lt "$deadline" ] || {
      echo "FAIL: Backup ${BACKUP} did not complete (last: ${phase:-<none>})" >&2
      kubectl -n "$NAMESPACE" describe backup.velero.io "$BACKUP" >&2 2>/dev/null || true
      kubectl -n "$NAMESPACE" logs deployment/velero --tail=100 >&2 2>/dev/null || true
      exit 1
    }
    sleep "$POLL"
  done
}

wait_restore() {
  local deadline=$(( $(date +%s) + DEADLINE_SECONDS )) phase errors
  while : ; do
    phase="$(kubectl -n "$NAMESPACE" get restore.velero.io "$RESTORE" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    errors="$(kubectl -n "$NAMESPACE" get restore.velero.io "$RESTORE" \
      -o jsonpath='{.status.errors}' 2>/dev/null || true)"
    case "$phase" in
      Completed)
        [ "${errors:-0}" = "0" ] || {
          echo "FAIL: Restore ${RESTORE} completed with ${errors} error(s)" >&2
          kubectl -n "$NAMESPACE" describe restore.velero.io "$RESTORE" >&2 2>/dev/null || true
          exit 1
        }
        return 0
        ;;
      Failed|PartiallyFailed)
        echo "FAIL: Restore ${RESTORE} ended in ${phase} (errors: ${errors:-unknown})" >&2
        kubectl -n "$NAMESPACE" describe restore.velero.io "$RESTORE" >&2 2>/dev/null || true
        exit 1
        ;;
    esac
    [ "$(date +%s)" -lt "$deadline" ] || {
      echo "FAIL: Restore ${RESTORE} did not complete (last: ${phase:-<none>})" >&2
      kubectl -n "$NAMESPACE" describe restore.velero.io "$RESTORE" >&2 2>/dev/null || true
      kubectl -n "$NAMESPACE" logs deployment/velero --tail=100 >&2 2>/dev/null || true
      exit 1
    }
    sleep "$POLL"
  done
}

echo "── smoke(velero): Deployment ${NAMESPACE}/velero Ready"
kubectl -n "$NAMESPACE" rollout status deployment/velero --timeout="$TIMEOUT" >/dev/null

echo "── smoke(velero): BackupStorageLocation ${NAMESPACE}/default Available"
deadline=$(( $(date +%s) + DEADLINE_SECONDS ))
while : ; do
  phase="$(kubectl -n "$NAMESPACE" get backupstoragelocation.velero.io default \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [ "$phase" = "Available" ] && break
  [ "$(date +%s)" -lt "$deadline" ] || {
    echo "FAIL: BackupStorageLocation default never became Available (last: ${phase:-<none>})" >&2
    kubectl -n "$NAMESPACE" get backupstoragelocation.velero.io default -o yaml >&2 2>/dev/null || true
    kubectl -n "$NAMESPACE" logs deployment/velero --tail=100 >&2 2>/dev/null || true
    exit 1
  }
  sleep "$POLL"
done

echo "── smoke(velero): Schedule ${NAMESPACE}/velero-critical-namespaces exists"
kubectl -n "$NAMESPACE" get schedule.velero.io velero-critical-namespaces >/dev/null

echo "── smoke(velero): scratch namespace ${SMOKE_NS} + ConfigMap marker"
kubectl create namespace "$SMOKE_NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$SMOKE_NS" create configmap smoke-marker \
  --from-literal=marker="$MARKER" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "── smoke(velero): Backup ${BACKUP} of namespace ${SMOKE_NS} -> Completed"
kubectl -n "$NAMESPACE" apply -f - <<EOF >/dev/null
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: ${BACKUP}
  namespace: ${NAMESPACE}
spec:
  includedNamespaces:
    - ${SMOKE_NS}
  storageLocation: default
  ttl: 1h
EOF
wait_backup

echo "── smoke(velero): deleting namespace ${SMOKE_NS} (the data must come from the backup)"
kubectl delete namespace "$SMOKE_NS" --wait=true --timeout="$TIMEOUT" >/dev/null
if kubectl get namespace "$SMOKE_NS" >/dev/null 2>&1; then
  echo "FAIL: namespace ${SMOKE_NS} still exists after delete" >&2
  exit 1
fi

echo "── smoke(velero): Restore ${RESTORE} from ${BACKUP} -> Completed"
kubectl -n "$NAMESPACE" apply -f - <<EOF >/dev/null
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: ${RESTORE}
  namespace: ${NAMESPACE}
spec:
  backupName: ${BACKUP}
  includedNamespaces:
    - ${SMOKE_NS}
  existingResourcePolicy: none
EOF
wait_restore

echo "── smoke(velero): restored namespace + ConfigMap marker ${MARKER}"
deadline=$(( $(date +%s) + DEADLINE_SECONDS ))
while : ; do
  marker="$(kubectl -n "$SMOKE_NS" get configmap smoke-marker \
    -o jsonpath='{.data.marker}' 2>/dev/null || true)"
  [ "$marker" = "$MARKER" ] && break
  [ "$(date +%s)" -lt "$deadline" ] || {
    echo "FAIL: restored ConfigMap marker '${marker:-<missing>}', expected '${MARKER}'" >&2
    kubectl -n "$SMOKE_NS" get configmap,all >&2 2>/dev/null || true
    kubectl -n "$NAMESPACE" describe restore.velero.io "$RESTORE" >&2 2>/dev/null || true
    exit 1
  }
  sleep "$POLL"
done

echo "[OK] smoke(velero): BSL Available, schedule present, backup ${BACKUP} Completed, restore ${RESTORE} Completed, marker recovered"
