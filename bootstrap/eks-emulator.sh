#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# eks-emulator.sh — the EKS substrate of the cloud emulator (dev/CI tooling only,
# docs/ci-cd.md). Floci backs `eks` with a real single-node k3s container (a live
# Kubernetes API server) and an OCI ECR registry; this script turns that into a
# kube-context the cluster smoke can boot the *full platform* on, so the smoke
# exercises EKS integration (IAM auth, kubeconfig, nodes) and the ECR image path
# in addition to the kind substrate.
#
# It is NOT a platform component: no sync-wave, no catalog row, nothing rendered
# by ArgoCD. It exists only for the duration of a smoke run.
#
# Lifecycle:
#   - start the Floci container on a dedicated Docker network (EKS mode), so the
#     k3s node Floci spawns can reach the emulator and pull from its ECR;
#   - create an IAM user + access key (Floci rejects the dummy test/test creds
#     for cluster-admin, so kubectl needs a real key);
#   - `aws eks create-cluster`, wait ACTIVE, `update-kubeconfig` (context
#     `floci-eks`), wait for the node to report Ready;
#   - publish the emulator into the cluster (Service + EndpointSlice) so the
#     cloud-integration smoke also runs against the EKS cluster.
#
# Usage:
#   eks-emulator.sh up       # Floci (EKS mode) + cluster + kubeconfig + publish
#   eks-emulator.sh down     # delete cluster/IAM/kubeconfig + emulator
#   eks-emulator.sh status
#
# Env: pins + emulator coordinates come from bootstrap/versions.sh and `.env`.
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

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ACTION="${1:-}"

EKS_CLUSTER="${FLOCI_EKS_CLUSTER:-sca-eks}"
EKS_CONTEXT="${FLOCI_EKS_CONTEXT:-floci-eks}"
EKS_REGION="${FLOCI_AWS_REGION:-us-east-1}"
EKS_ACCOUNT="${FLOCI_AWS_ACCOUNT:-000000000000}"
EKS_ROLE_ARN="${FLOCI_EKS_ROLE_ARN:-arn:aws:iam::${EKS_ACCOUNT}:role/eks-role}"
EKS_SUBNET="${FLOCI_EKS_SUBNET:-subnet-default-us-east-1-a}"
IAM_USER="${FLOCI_EKS_IAM_USER:-eks-admin}"
ECR_REPO="${FLOCI_EKS_ECR_REPO:-sca-smoke}"
CLOUD_NETWORK="${FLOCI_EKS_NETWORK:-sca-eks}"
FLOCI_NAME="${FLOCI_NAME:-floci}"
FLOCI_PORT="${FLOCI_PORT:-4566}"
ENDPOINT="http://127.0.0.1:${FLOCI_PORT}"
EKS_ADMIN_FILE=".secrets/eks-admin.env"
NODE_TIMEOUT="${SMOKE_TIMEOUT:-900}"

[ -n "$ACTION" ] || { echo "usage: $0 up|down|status" >&2; exit 2; }

# ── AWS CLI via the pinned image ─────────────────────────────────────────────
# The repo pins AWS_CLI_IMAGE and never installs an unpinned aws binary on the
# host/runner. `--network host` lets the container reach Floci's host port; the
# ad-hoc ~/.kube mount is what `update-kubeconfig` writes into.
#
# AWS_CLI_ENV carries optional extra `-e KEY=val` args (empty by default).
# eks_up uses it to disable the CLI's client-side retries around a call whose
# retry is not idempotent (see there).
AWS_CLI_ENV=()
aws_cli() {
  docker run --rm --network host \
    -v "${HOME}/.kube:/root/.kube" \
    -e AWS_ENDPOINT_URL="${ENDPOINT}" \
    -e AWS_DEFAULT_REGION="${EKS_REGION}" \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}" \
    ${AWS_CLI_ENV[@]+"${AWS_CLI_ENV[@]}"} \
    "${AWS_CLI_IMAGE}" "$@"
}

wait_for_api() {
  # A published port is not a ready API: docker-proxy accepts the connection the
  # moment the port is mapped, before Floci can answer. Poll a real call so a
  # transient failure cannot be mistaken for a missing cluster.
  local i=0
  while ! aws_cli eks list-clusters --query 'clusters' --output text >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -lt 60 ] || { echo "ERROR: cloud emulator API not ready on ${ENDPOINT}" >&2; return 1; }
    sleep 2
  done
}

cluster_status() {
  # ACTIVE/CREATING/... when the cluster exists, ABSENT when Floci reports it
  # does not exist (describe 404), UNKNOWN when the call failed for any other
  # reason (e.g. transient). The distinction is load-bearing: only a definite
  # ABSENT may trigger create-cluster.
  local out
  if out="$(aws_cli eks describe-cluster --name "${EKS_CLUSTER}" \
        --query 'cluster.status' --output text 2>&1)"; then
    printf '%s\n' "${out}"
  elif printf '%s' "${out}" | grep -q 'ResourceNotFoundException'; then
    printf 'ABSENT\n'
  else
    printf 'UNKNOWN\n'
  fi
}

wait_for_cluster_active() {
  echo "── eks: waiting for cluster '${EKS_CLUSTER}' to become ACTIVE (timeout ${NODE_TIMEOUT}s)"
  local deadline now status
  deadline=$(( $(date +%s) + NODE_TIMEOUT ))
  while : ; do
    status="$(cluster_status)"
    case "${status}" in
      ACTIVE) echo "  cluster ACTIVE"; return 0 ;;
      FAILED) echo "ERROR: cluster '${EKS_CLUSTER}' FAILED" >&2; return 1 ;;
    esac
    now="$(date +%s)"
    [ "${now}" -lt "${deadline}" ] || {
      echo "ERROR: cluster '${EKS_CLUSTER}' not ACTIVE within ${NODE_TIMEOUT}s (last status: ${status:-unknown})" >&2
      return 1
    }
    sleep 5
  done
}

ensure_iam_admin() {
  # Create (idempotently) the IAM user and reuse a saved access key if present,
  # otherwise mint one. Export the key so later aws_cli calls (eks) use it.
  mkdir -p .secrets
  chmod 700 .secrets 2>/dev/null || true
  if [ -f "${EKS_ADMIN_FILE}" ]; then
    # shellcheck disable=SC1090,SC1091
    . "${EKS_ADMIN_FILE}"
    if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
      echo "  reusing saved admin access key for '${IAM_USER}'"
      return 0
    fi
  fi

  echo "── eks: creating IAM user '${IAM_USER}' + access key"
  aws_cli iam create-user --user-name "${IAM_USER}" >/dev/null 2>&1 || true
  local key
  key="$(aws_cli iam create-access-key --user-name "${IAM_USER}" \
    --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)"
  AWS_ACCESS_KEY_ID="$(printf '%s' "$key" | awk '{print $1}')"
  AWS_SECRET_ACCESS_KEY="$(printf '%s' "$key" | awk '{print $2}')"
  [ -n "${AWS_ACCESS_KEY_ID}" ] && [ -n "${AWS_SECRET_ACCESS_KEY}" ] \
    || { echo "ERROR: could not parse the created access key" >&2; return 1; }
  umask 077
  printf 'AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\n' \
    "${AWS_ACCESS_KEY_ID}" "${AWS_SECRET_ACCESS_KEY}" > "${EKS_ADMIN_FILE}"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
}

rename_context() {
  # `update-kubeconfig` names the context after the cluster ARN; give it the
  # stable alias the smoke uses, and make it current.
  local current
  current="$(kubectl config current-context 2>/dev/null || true)"
  if [ -n "${current}" ] && [ "${current}" != "${EKS_CONTEXT}" ]; then
    kubectl config rename-context "${current}" "${EKS_CONTEXT}" >/dev/null 2>&1 || true
  fi
  kubectl config use-context "${EKS_CONTEXT}" >/dev/null 2>&1 || true
}

wait_for_nodes() {
  echo "── eks: waiting for a node to report Ready (timeout ${NODE_TIMEOUT}s)"
  local deadline now
  deadline=$(( $(date +%s) + NODE_TIMEOUT ))
  while : ; do
    now="$(date +%s)"
    [ "${now}" -lt "${deadline}" ] || {
      echo "ERROR: no Ready node in cluster '${EKS_CLUSTER}' within ${NODE_TIMEOUT}s" >&2
      kubectl --context "${EKS_CONTEXT}" get nodes -o wide 2>/dev/null || true
      return 1
    }
    if kubectl --context "${EKS_CONTEXT}" get nodes --no-headers 2>/dev/null | grep -q ' Ready '; then
      kubectl --context "${EKS_CONTEXT}" get nodes -o wide
      return 0
    fi
    sleep 5
  done
}

eks_up() {
  echo "── eks: starting cloud emulator on network '${CLOUD_NETWORK}' (EKS mode)"
  CLOUD_NETWORK="${CLOUD_NETWORK}" "${SELF_DIR}/cloud-emulator.sh" start "${CLOUD_PROVIDER:-aws}"
  wait_for_api

  ensure_iam_admin

  local status
  status="$(cluster_status)"
  if [ "${status}" = "ACTIVE" ]; then
    echo "[skip] EKS cluster '${EKS_CLUSTER}' already ACTIVE"
  else
    if [ "${status}" = "ABSENT" ] || [ "${status}" = "UNKNOWN" ]; then
      echo "── eks: creating cluster '${EKS_CLUSTER}' (role ${EKS_ROLE_ARN})"
      # Floci's create-cluster is not idempotent while it provisions: the handler
      # blocks on the k3s container and records the cluster only once it is up,
      # so a request the AWS CLI retries past its (~5s) client-side window
      # provisions a *second* k3s container — Floci then removes the first as
      # stale and the cluster is left in a broken state, or the retry answers
      # ResourceInUseException for the very cluster it just registered (the CI
      # failure). So: one request, no client retries (AWS_MAX_ATTEMPTS=1); retry
      # policy lives in wait_for_cluster_active below. The create verdict is not
      # a source of truth — converge on the cluster state instead.
      local create_err
      AWS_CLI_ENV=(-e AWS_MAX_ATTEMPTS=1)
      if ! create_err="$(aws_cli eks create-cluster \
            --name "${EKS_CLUSTER}" \
            --role-arn "${EKS_ROLE_ARN}" \
            --resources-vpc-config "subnetIds=${EKS_SUBNET}" 2>&1)"; then
        printf '%s\n' "${create_err}" | sed 's/^/  /' >&2
        echo "  create-cluster returned an error; converging on the cluster state" >&2
      fi
      AWS_CLI_ENV=()
    else
      echo "  cluster '${EKS_CLUSTER}' already present (status ${status}); waiting for ACTIVE"
    fi
    wait_for_cluster_active
  fi

  echo "── eks: fetching kubeconfig (context ${EKS_CONTEXT})"
  aws_cli eks update-kubeconfig --name "${EKS_CLUSTER}" --kubeconfig /root/.kube/config --endpoint-url "${ENDPOINT}" >/dev/null
  rename_context
  wait_for_nodes

  echo "── eks: publishing cloud emulator into the EKS cluster"
  CLOUD_NETWORK="${CLOUD_NETWORK}" "${SELF_DIR}/cloud-emulator.sh" publish "${CLOUD_PROVIDER:-aws}"

  echo ""
  echo "[OK] EKS substrate ready: context '${EKS_CONTEXT}', cluster '${EKS_CLUSTER}'"
  echo "Next: make bootstrap ENV=local   (bootstrap the platform onto it)"
}

eks_down() {
  echo "── eks: deleting cluster '${EKS_CLUSTER}'"
  aws_cli eks delete-cluster --name "${EKS_CLUSTER}" >/dev/null 2>&1 || true

  if [ -f "${EKS_ADMIN_FILE}" ]; then
    # shellcheck disable=SC1090,SC1091
    . "${EKS_ADMIN_FILE}"
    echo "── eks: deleting IAM user '${IAM_USER}' (and its access keys)"
    aws_cli iam list-access-keys --user-name "${IAM_USER}" \
      --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null \
      | tr '\t' '\n' | while read -r kid; do
        [ -n "${kid}" ] || continue
        aws_cli iam delete-access-key --user-name "${IAM_USER}" --access-key-id "${kid}" >/dev/null 2>&1 || true
      done
    aws_cli iam delete-user --user-name "${IAM_USER}" >/dev/null 2>&1 || true
    rm -f "${EKS_ADMIN_FILE}"
  fi

  echo "── eks: removing kubeconfig context '${EKS_CONTEXT}'"
  kubectl config delete-context "${EKS_CONTEXT}" >/dev/null 2>&1 || true

  echo "── eks: tearing down cloud emulator"
  CLOUD_NETWORK="${CLOUD_NETWORK}" "${SELF_DIR}/cloud-emulator.sh" down "${CLOUD_PROVIDER:-aws}" || true
  docker network rm "${CLOUD_NETWORK}" >/dev/null 2>&1 || true
  echo "[OK] EKS substrate removed"
}

eks_status() {
  echo "── eks: cluster '${EKS_CLUSTER}'"
  # The kubeconfig authenticates through `aws eks get-token`, so export the admin
  # key here too — `status` is typically run in a fresh shell after `up`.
  if [ -f "${EKS_ADMIN_FILE}" ]; then
    # shellcheck disable=SC1090,SC1091
    . "${EKS_ADMIN_FILE}"
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  fi
  local status
  status="$(cluster_status)"
  case "${status}" in
    ABSENT) status="absent" ;;
    UNKNOWN) status="unknown (describe failed)" ;;
  esac
  echo "  aws eks: ${status}"
  echo "  context: ${EKS_CONTEXT}"
  if kubectl --context "${EKS_CONTEXT}" get nodes >/dev/null 2>&1; then
    kubectl --context "${EKS_CONTEXT}" get nodes -o wide
  else
    echo "  nodes: context '${EKS_CONTEXT}' not reachable" >&2
    return 1
  fi
}

case "$ACTION" in
  up) eks_up ;;
  down) eks_down ;;
  status) eks_status ;;
  *) echo "usage: $0 up|down|status" >&2; exit 2 ;;
esac
