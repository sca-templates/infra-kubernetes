#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-velero.sh — verify Velero is operational against Floci S3: the server is
# Ready, the default BackupStorageLocation is Available, the
# `velero-critical-namespaces` schedule exists, and a real Backup of the
# `default` namespace completes.
#
# Selective smoke for the velero component; driven by
# `make smoke COMPONENT=velero` (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${VELERO_NAMESPACE:-velero}"
TIMEOUT="${SMOKE_TIMEOUT:-600s}"
DEADLINE_SECONDS="${SMOKE_DEADLINE:-900}"
POLL="${SMOKE_POLL:-5}"
BACKUP="velero-smoke-$(date +%s)-$$"

cleanup() {
  kubectl -n "$NAMESPACE" delete backup.velero.io "$BACKUP" \
    --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

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

echo "── smoke(velero): Backup ${BACKUP} of namespace default -> Completed"
kubectl -n "$NAMESPACE" apply -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: ${BACKUP}
  namespace: ${NAMESPACE}
spec:
  includedNamespaces:
    - default
  storageLocation: default
  ttl: 1h
EOF

deadline=$(( $(date +%s) + DEADLINE_SECONDS ))
while : ; do
  phase="$(kubectl -n "$NAMESPACE" get backup.velero.io "$BACKUP" \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "$phase" in
    Completed)
      break
      ;;
    Failed|PartiallyFailed)
      echo "FAIL: Backup ${BACKUP} ended in ${phase}" >&2
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

echo "[OK] smoke(velero): BSL Available, schedule present, backup ${BACKUP} Completed"
