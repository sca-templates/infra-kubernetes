#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-cloud-aws.sh — generic cloud-integration smoke for the `aws` provider.
# Proves the cluster can reach the emulated AWS endpoint and actually operate
# against it: from inside the cluster, a throwaway Job runs the pinned AWS CLI
# to create an S3 bucket, put and get an object back, and list the bucket
# again. No cloud account, no IAM, no per-component configuration — just an
# endpoint plus the same dummy credentials every smoke uses.
#
# The emulator is a prerequisite: bootstrap/cloud-emulator.sh must have
# published it (bootstrap/smoke-ci.sh does this automatically). Driven by
# `make smoke COMPONENT=cloud` (see docs/ci-cd.md).
set -euo pipefail

# Load the local `.env` seam if present (same behaviour as bootstrap/sca.sh):
# a KEY=value line becomes a shell variable here, so `.env` overrides win over
# the pinned defaults in versions.sh below.
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

CLOUD_NAMESPACE="${CLOUD_NAMESPACE:-cloud}"
SCRATCH_NS="${CLOUD_SMOKE_NS:-cloud-smoke}"
FLOCI_NAME="${FLOCI_NAME:-floci}"
FLOCI_PORT="${FLOCI_PORT:-4566}"
ENDPOINT="http://${FLOCI_NAME}.${CLOUD_NAMESPACE}.svc.cluster.local:${FLOCI_PORT}"
JOB_NAME="cloud-smoke-aws"
BUCKET="sca-smoke-$(date +%s)-$$"
TIMEOUT="${SMOKE_TIMEOUT:-180}"
POLL="${SMOKE_POLL:-5}"

cleanup() {
  kubectl delete namespace "$SCRATCH_NS" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "── smoke(cloud/aws): emulator Service/${FLOCI_NAME} in ns ${CLOUD_NAMESPACE}"
kubectl -n "${CLOUD_NAMESPACE}" get svc "${FLOCI_NAME}" >/dev/null || {
  echo "FAIL: Service/${FLOCI_NAME} not present — run 'make cloud-up' first" >&2
  exit 1
}

echo "── smoke(cloud/aws): throwing a Job at ${ENDPOINT}"
kubectl create namespace "$SCRATCH_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$SCRATCH_NS" delete job "$JOB_NAME" --ignore-not-found >/dev/null 2>&1 || true
kubectl -n "$SCRATCH_NS" apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${SCRATCH_NS}
  labels:
    app.kubernetes.io/name: ${JOB_NAME}
    app.kubernetes.io/part-of: sca-cloud-smoke
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${JOB_NAME}
    spec:
      restartPolicy: Never
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
            - name: AWS_ACCESS_KEY_ID
              value: test
            - name: AWS_SECRET_ACCESS_KEY
              value: test
            - name: AWS_DEFAULT_REGION
              value: us-east-1
            - name: AWS_ENDPOINT_URL
              value: ${ENDPOINT}
            - name: BUCKET
              value: ${BUCKET}
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: false
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: tmp
              mountPath: /tmp
          args:
            - |
              set -eu
              mkdir -p "\${HOME}/.aws"
              printf '[default]\nregion = us-east-1\ns3 =\n  addressing_style = path\n' > "\${HOME}/.aws/config"
              echo "-- endpoint \${AWS_ENDPOINT_URL}"
              aws --endpoint-url "\${AWS_ENDPOINT_URL}" s3api create-bucket --bucket "\${BUCKET}"
              aws --endpoint-url "\${AWS_ENDPOINT_URL}" s3api list-buckets --query "Buckets[?Name=='\${BUCKET}'] | [0].Name" --output text
              printf 'hello-floci\n' > /tmp/obj
              aws --endpoint-url "\${AWS_ENDPOINT_URL}" s3api put-object --bucket "\${BUCKET}" --key smoke.txt --body /tmp/obj >/dev/null
              aws --endpoint-url "\${AWS_ENDPOINT_URL}" s3api get-object --bucket "\${BUCKET}" --key smoke.txt /tmp/out >/dev/null
              grep -q 'hello-floci' /tmp/out
              echo "AWS_SMOKE_OK bucket=\${BUCKET}"
      volumes:
        - name: tmp
          emptyDir: {}
EOF

echo "── smoke(cloud/aws): waiting for Job/${JOB_NAME} to finish (timeout ${TIMEOUT}s)"
deadline=$(( $(date +%s) + TIMEOUT ))
while : ; do
  phase="$(kubectl -n "$SCRATCH_NS" get job "$JOB_NAME" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || true)"
  failed="$(kubectl -n "$SCRATCH_NS" get job "$JOB_NAME" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || true)"
  if [ "$phase" = "True" ]; then
    echo "[OK] Job/${JOB_NAME} completed"
    break
  fi
  if [ "$failed" = "True" ]; then
    echo "FAIL: Job/${JOB_NAME} failed (cloud integration against ${ENDPOINT})" >&2
    kubectl -n "$SCRATCH_NS" get job "$JOB_NAME" -o yaml >&2 2>/dev/null || true
    echo "--- logs of the Job pod" >&2
    kubectl -n "$SCRATCH_NS" logs "job/${JOB_NAME}" --tail=200 >&2 2>/dev/null || true
    exit 1
  fi
  [ "$(date +%s)" -lt "$deadline" ] || {
    echo "FAIL: Job/${JOB_NAME} did not finish within ${TIMEOUT}s" >&2
    kubectl -n "$SCRATCH_NS" get pods -o wide >&2 2>/dev/null || true
    echo "--- logs of the Job pod" >&2
    kubectl -n "$SCRATCH_NS" logs "job/${JOB_NAME}" --tail=200 >&2 2>/dev/null || true
    exit 1
  }
  sleep "$POLL"
done

out="$(kubectl -n "$SCRATCH_NS" logs "job/${JOB_NAME}" --tail=50 2>/dev/null || true)"
printf '%s\n' "$out" | grep -q 'AWS_SMOKE_OK' || {
  echo "FAIL: Job/${JOB_NAME} finished but did not report AWS_SMOKE_OK" >&2
  printf '%s\n' "$out" >&2
  exit 1
}

echo "[OK] smoke(cloud/aws): created bucket, round-tripped an object via ${ENDPOINT}"
