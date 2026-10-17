#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-eks.sh — EKS-substrate smoke (dev/CI tooling only, docs/ci-cd.md). Runs
# against the Floci-emulated EKS cluster (context `floci-eks`) and proves the
# two EKS-specific paths the kind substrate cannot: the cluster is a real
# Kubernetes API server reached through an IAM-authenticated kubeconfig, and
# images pushed to the emulated ECR registry are pullable in-cluster (the k3s
# containerd registry mirror Floci injects at cluster creation).
#
# The emulator + cluster are a prerequisite: bootstrap/eks-emulator.sh must have
# brought them up (bootstrap/smoke-ci.sh does this for the `eks` substrate).
# Driven by `make smoke COMPONENT=eks`.
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

# Reuse the EKS admin key minted by eks-emulator.sh (Floci rejects the dummy
# test/test creds for the EKS control plane; the ECR API calls use the same
# admin credentials). Absent only if the cluster was brought up out of band.
if [ -f ".secrets/eks-admin.env" ]; then
  # shellcheck disable=SC1090,SC1091
  . ".secrets/eks-admin.env"
fi

EKS_CLUSTER="${FLOCI_EKS_CLUSTER:-sca-eks}"
EKS_CONTEXT="${FLOCI_EKS_CONTEXT:-floci-eks}"
EKS_REGION="${FLOCI_AWS_REGION:-us-east-1}"
EKS_ACCOUNT="${FLOCI_AWS_ACCOUNT:-000000000000}"
FLOCI_PORT="${FLOCI_PORT:-4566}"
ENDPOINT="http://127.0.0.1:${FLOCI_PORT}"
ECR_REPO="${FLOCI_EKS_ECR_REPO:-sca-smoke}"
SCRATCH_NS="${EKS_SMOKE_NS:-eks-smoke}"
JOB_NAME="eks-smoke-ecr"
REGISTRY="${EKS_ACCOUNT}.dkr.ecr.${EKS_REGION}.localhost:${FLOCI_PORT}"
TIMEOUT="${SMOKE_TIMEOUT:-300}"
POLL="${SMOKE_POLL:-5}"

# Tag the pushed artifact after the pinned image's own tag (never `latest`).
image_tag="${AWS_CLI_IMAGE##*:}"
case "${AWS_CLI_IMAGE}" in
  *:*) : ;;
  *) image_tag="smoke" ;;
esac

aws_cli() {
  docker run --rm --network host \
    -e AWS_ENDPOINT_URL="${ENDPOINT}" \
    -e AWS_DEFAULT_REGION="${EKS_REGION}" \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}" \
    "${AWS_CLI_IMAGE}" "$@"
}

cleanup() {
  kubectl --context "${EKS_CONTEXT}" delete namespace "$SCRATCH_NS" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "── smoke(eks): context '${EKS_CONTEXT}', cluster '${EKS_CLUSTER}'"
kubectl --context "${EKS_CONTEXT}" get nodes --no-headers 2>/dev/null | grep -q ' Ready ' || {
  echo "FAIL: no Ready node on context '${EKS_CONTEXT}' — run 'make eks-up' first" >&2
  exit 1
}
echo "[OK] EKS API reachable with a Ready node"

echo "── smoke(eks): ensuring ECR repository '${ECR_REPO}'"
aws_cli ecr create-repository --repository-name "${ECR_REPO}" >/dev/null 2>&1 || true
aws_cli ecr describe-repositories --repository-names "${ECR_REPO}" \
  --query 'repositories[0].repositoryUri' --output text

echo "── smoke(eks): pushing ${AWS_CLI_IMAGE} to ${REGISTRY}/${ECR_REPO}:${image_tag}"
aws_cli ecr get-login-password --region "${EKS_REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}" >/dev/null
docker pull "${AWS_CLI_IMAGE}" >/dev/null
docker tag "${AWS_CLI_IMAGE}" "${REGISTRY}/${ECR_REPO}:${image_tag}"
docker push "${REGISTRY}/${ECR_REPO}:${image_tag}" >/dev/null
aws_cli ecr describe-images --repository-name "${ECR_REPO}" \
  --query "imageDetails[?contains(imageTags, '${image_tag}')].imageTags[0]" --output text \
  | grep -q "${image_tag}" || { echo "FAIL: pushed image not found in ECR" >&2; exit 1; }
echo "[OK] image pushed to ECR"

echo "── smoke(eks): pulling it in-cluster via the node registry mirror"
kubectl --context "${EKS_CONTEXT}" create namespace "$SCRATCH_NS" --dry-run=client -o yaml | kubectl --context "${EKS_CONTEXT}" apply -f - >/dev/null
kubectl --context "${EKS_CONTEXT}" -n "$SCRATCH_NS" delete job "$JOB_NAME" --ignore-not-found >/dev/null 2>&1 || true
kubectl --context "${EKS_CONTEXT}" -n "$SCRATCH_NS" apply -f - <<EOF >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${SCRATCH_NS}
  labels:
    app.kubernetes.io/name: ${JOB_NAME}
    app.kubernetes.io/part-of: sca-eks-smoke
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
        - name: ecr-pull
          image: ${REGISTRY}/${ECR_REPO}:${image_tag}
          command: ["/bin/sh", "-ec"]
          args:
            - |
              aws --version
              echo "EKS_ECR_PULL_OK"
EOF

echo "── smoke(eks): waiting for Job/${JOB_NAME} (timeout ${TIMEOUT}s)"
deadline=$(( $(date +%s) + TIMEOUT ))
while : ; do
  complete="$(kubectl --context "${EKS_CONTEXT}" -n "$SCRATCH_NS" get job "$JOB_NAME" \
    -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || true)"
  failed="$(kubectl --context "${EKS_CONTEXT}" -n "$SCRATCH_NS" get job "$JOB_NAME" \
    -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || true)"
  [ "$complete" = "True" ] && break
  if [ "$failed" = "True" ]; then
    echo "FAIL: Job/${JOB_NAME} failed pulling ${REGISTRY}/${ECR_REPO}:${image_tag}" >&2
    kubectl --context "${EKS_CONTEXT}" -n "$SCRATCH_NS" describe pod -l "app.kubernetes.io/name=${JOB_NAME}" >&2 2>/dev/null || true
    kubectl --context "${EKS_CONTEXT}" -n "$SCRATCH_NS" logs "job/${JOB_NAME}" --tail=200 >&2 2>/dev/null || true
    exit 1
  fi
  [ "$(date +%s)" -lt "$deadline" ] || {
    echo "FAIL: Job/${JOB_NAME} did not finish within ${TIMEOUT}s" >&2
    kubectl --context "${EKS_CONTEXT}" -n "$SCRATCH_NS" get pods -o wide >&2 2>/dev/null || true
    kubectl --context "${EKS_CONTEXT}" -n "$SCRATCH_NS" describe pod -l "app.kubernetes.io/name=${JOB_NAME}" >&2 2>/dev/null || true
    exit 1
  }
  sleep "$POLL"
done

out="$(kubectl --context "${EKS_CONTEXT}" -n "$SCRATCH_NS" logs "job/${JOB_NAME}" --tail=50 2>/dev/null || true)"
printf '%s\n' "$out" | grep -q 'EKS_ECR_PULL_OK' || {
  echo "FAIL: Job/${JOB_NAME} finished but did not report EKS_ECR_PULL_OK" >&2
  printf '%s\n' "$out" >&2
  exit 1
}

echo "[OK] smoke(eks): ECR push + in-cluster pull round-tripped via ${REGISTRY}"
