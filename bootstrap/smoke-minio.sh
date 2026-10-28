#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-minio.sh — verify the local MinIO stand-in and its backup buckets: the
# ExternalSecret projected the Vault root credential, the chart's Deployment
# is Ready, the minio-buckets Job created the buckets, and a throwaway
# in-cluster AWS CLI Job can authenticate and round-trip an object.
#
# Selective smoke for the minio component; driven by
# `make smoke COMPONENT=minio` (see docs/ci-cd.md).
set -euo pipefail

# Load the local `.env` seam if present (same behaviour as bootstrap/sca.sh).
for _sca_env in "$(dirname "$0")/../.env" ".env"; do
  if [ -f "$_sca_env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$_sca_env"
    break
  fi
done
unset _sca_env

# shellcheck source=bootstrap/versions.sh
. "$(dirname "$0")/versions.sh"

NAMESPACE="${MINIO_NAMESPACE:-minio}"
TIMEOUT="${SMOKE_TIMEOUT:-300s}"
DEADLINE_SECONDS="${SMOKE_DEADLINE:-600}"
POLL="${SMOKE_POLL:-5}"
JOB_NAME="minio-smoke"
KEY="smoke-$(date +%s)-$$"

cleanup() {
  kubectl -n "$NAMESPACE" delete job "$JOB_NAME" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "── smoke(minio): ExternalSecret ${NAMESPACE}/minio-root-credentials SecretSynced"
for attempt in {1..120}; do
  reason="$(kubectl -n "$NAMESPACE" get externalsecret minio-root-credentials \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || true)"
  [ "$reason" = "SecretSynced" ] && break
  [ "$attempt" -eq 120 ] && {
    echo "FAIL: ExternalSecret ${NAMESPACE}/minio-root-credentials never reached SecretSynced (last: ${reason:-<none>})" >&2
    kubectl -n "$NAMESPACE" get externalsecret minio-root-credentials -o yaml >&2 2>/dev/null || true
    exit 1
  }
  sleep 5
done

echo "── smoke(minio): Deployment ${NAMESPACE}/minio Ready"
kubectl -n "$NAMESPACE" rollout status deployment/minio --timeout="$TIMEOUT" >/dev/null
kubectl -n "$NAMESPACE" wait --for=condition=Ready pod \
  -l app=minio,release=minio --timeout="$TIMEOUT" >/dev/null

echo "── smoke(minio): Job ${NAMESPACE}/minio-buckets Complete"
kubectl -n "$NAMESPACE" wait --for=condition=Complete job/minio-buckets --timeout="$TIMEOUT" >/dev/null

echo "── smoke(minio): throwing an AWS CLI Job at ${NAMESPACE}/minio"
kubectl -n "$NAMESPACE" delete job "$JOB_NAME" --ignore-not-found >/dev/null 2>&1 || true
kubectl -n "$NAMESPACE" apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${JOB_NAME}
    app.kubernetes.io/part-of: sca-minio-smoke
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${JOB_NAME}
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: aws
          image: ${AWS_CLI_IMAGE}
          command: ["/bin/sh", "-ec"]
          env:
            - name: HOME
              value: /tmp
            - name: KEY
              value: ${KEY}
            - name: AWS_DEFAULT_REGION
              value: minio
            - name: AWS_ENDPOINT_URL
              value: http://minio.minio.svc.cluster.local:9000
            - name: AWS_EC2_METADATA_DISABLED
              value: "true"
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: minio-root-credentials
                  key: rootUser
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: minio-root-credentials
                  key: rootPassword
          args:
            - |
              set -eu
              mkdir -p "\${HOME}/.aws"
              printf '[default]\nregion = minio\ns3 =\n  addressing_style = path\n' > "\${HOME}/.aws/config"
              aws --endpoint-url "\${AWS_ENDPOINT_URL}" s3api list-buckets --query 'Buckets[].Name' --output text
              for bucket in velero vault-snapshots cnpg-backups; do
                aws --endpoint-url "\${AWS_ENDPOINT_URL}" s3api head-bucket --bucket "\${bucket}"
              done
              printf 'hello-minio\n' > /tmp/obj
              aws --endpoint-url "\${AWS_ENDPOINT_URL}" s3api put-object --bucket velero --key "\${KEY}.txt" --body /tmp/obj >/dev/null
              aws --endpoint-url "\${AWS_ENDPOINT_URL}" s3api get-object --bucket velero --key "\${KEY}.txt" /tmp/out >/dev/null
              grep -q 'hello-minio' /tmp/out
              aws --endpoint-url "\${AWS_ENDPOINT_URL}" s3api delete-object --bucket velero --key "\${KEY}.txt" >/dev/null
              echo "MINIO_SMOKE_OK"
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
EOF

echo "── smoke(minio): waiting for Job/${JOB_NAME} to finish"
deadline=$(( $(date +%s) + DEADLINE_SECONDS ))
while : ; do
  done_status="$(kubectl -n "$NAMESPACE" get job "$JOB_NAME" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || true)"
  failed="$(kubectl -n "$NAMESPACE" get job "$JOB_NAME" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || true)"
  if [ "$done_status" = "True" ]; then
    echo "[OK] Job/${JOB_NAME} completed"
    break
  fi
  if [ "$failed" = "True" ]; then
    echo "FAIL: Job/${JOB_NAME} failed (MinIO auth/endpoint)" >&2
    kubectl -n "$NAMESPACE" get job "$JOB_NAME" -o yaml >&2 2>/dev/null || true
    kubectl -n "$NAMESPACE" logs "job/${JOB_NAME}" --tail=200 >&2 2>/dev/null || true
    exit 1
  fi
  [ "$(date +%s)" -lt "$deadline" ] || {
    echo "FAIL: Job/${JOB_NAME} did not finish within ${TIMEOUT}" >&2
    kubectl -n "$NAMESPACE" get pods -o wide >&2 2>/dev/null || true
    kubectl -n "$NAMESPACE" logs "job/${JOB_NAME}" --tail=200 >&2 2>/dev/null || true
    exit 1
  }
  sleep "$POLL"
done

out="$(kubectl -n "$NAMESPACE" logs "job/${JOB_NAME}" --tail=50 2>/dev/null || true)"
printf '%s\n' "$out" | grep -q 'MINIO_SMOKE_OK' || {
  echo "FAIL: Job/${JOB_NAME} finished but did not report MINIO_SMOKE_OK" >&2
  printf '%s\n' "$out" >&2
  exit 1
}

echo "[OK] smoke(minio): buckets velero/vault-snapshots/cnpg-backups usable"
