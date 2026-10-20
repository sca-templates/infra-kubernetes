#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# eks-emulator.sh — the EKS substrate of the cloud emulator (dev/CI tooling only,
# docs/ci-cd.md). Floci backs `eks` with a real single-node k3s container (a live
# Kubernetes API server) and an OCI ECR registry; this script turns that into a
# kube-context the cluster smoke can boot the *full platform* on, so the smoke
# exercises EKS integration (IAM auth, kubeconfig, nodes) and the ECR image path
# on the very substrate production runs on.
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
# A short window to see the first Node object after the cluster reports ACTIVE.
# Floci records the cluster row before the k3s node is up, and a create whose
# server-side connection dropped can leave that row ACTIVE with no node at all
# (see eks_up): the node has to appear soon or the cluster is treated as broken.
NODE_APPEAR_TIMEOUT="${NODE_APPEAR_TIMEOUT:-90}"
DIAGNOSE_DIR="${SMOKE_DIAGNOSE_DIR:-.generated}"

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
  ensure_kube_dir
  docker run --rm --network host \
    -v "${HOME}/.kube:/root/.kube" \
    -e AWS_ENDPOINT_URL="${ENDPOINT}" \
    -e AWS_DEFAULT_REGION="${EKS_REGION}" \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}" \
    ${AWS_CLI_ENV[@]+"${AWS_CLI_ENV[@]}"} \
    "${AWS_CLI_IMAGE}" "$@"
}

# A missing ${HOME}/.kube is created by dockerd (root) for the aws_cli bind
# mount, and `update-kubeconfig` then writes a 0600 root-owned file the host
# kubectl cannot read: every `kubectl --context floci-eks` fails with
# "permission denied" — an error the node waits used to silence, surfacing as
# the observed "cluster ACTIVE but no node appeared". Pre-create the dir and
# file as the invoking user so the container's in-place rewrite keeps the user
# as owner. Called from aws_cli itself: the very first call (wait_for_api)
# already mounts it.
ensure_kube_dir() {
  mkdir -p "${HOME}/.kube" 2>/dev/null || true
  kubeconfig_ownership
  mkdir -p "${HOME}/.kube"
  [ -e "${HOME}/.kube/config" ] || : > "${HOME}/.kube/config"
}

kubeconfig_ownership() {
  # The bind mount (or a container that replaced the config inode) can leave
  # ~/.kube root-owned: hand it back to the invoking user via a root container
  # (root can chown arbitrary host files — no userns remap on the runners).
  [ -d "${HOME}/.kube" ] || return 0
  if [ -w "${HOME}/.kube" ] && { [ ! -e "${HOME}/.kube/config" ] || [ -w "${HOME}/.kube/config" ]; }; then
    return 0
  fi
  echo "  fixing ownership of ${HOME}/.kube (written as root by docker)"
  docker run --rm -v "${HOME}/.kube:/kcfg" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    --entrypoint sh "${AWS_CLI_IMAGE}" \
    -c 'chown -R "$HOST_UID:$HOST_GID" /kcfg'
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

diagnose_kubectl() {
  # The node waits silence kubectl's stderr, which made a client-side failure
  # (missing context, unreadable config) indistinguishable from a cluster with
  # no node. Keep a stderr-visible dump in the uploaded artifacts.
  local out="${DIAGNOSE_DIR}/eks-node-failure.kubectl.txt"
  mkdir -p "${DIAGNOSE_DIR}"
  {
    echo "# whoami: $(id -un) ($(id -u):$(id -g))"
    echo "# ls -l ${HOME}/.kube"
    ls -la "${HOME}/.kube" 2>&1 || true
    echo "# kubectl config current-context"
    kubectl config current-context 2>&1 || true
    echo "# kubectl config get-contexts"
    kubectl config get-contexts 2>&1 || true
    echo "# kubectl --context ${EKS_CONTEXT} get nodes -o wide"
    kubectl --context "${EKS_CONTEXT}" get nodes -o wide 2>&1 || true
    echo "# kubectl version --request-timeout=10s"
    kubectl version --request-timeout=10s 2>&1 || true
  } > "${out}" || true
  echo "  wrote ${out}" >&2
}

rename_context() {
  # `update-kubeconfig --alias` already names the context; this stays as a
  # fallback for a kubeconfig written before the alias existed. verify_kubecontext
  # below fails loudly, so nothing here needs to be trusted.
  local current
  current="$(kubectl config current-context 2>/dev/null || true)"
  if [ -n "${current}" ] && [ "${current}" != "${EKS_CONTEXT}" ]; then
    kubectl config rename-context "${current}" "${EKS_CONTEXT}" >/dev/null 2>&1 || true
    kubectl config use-context "${EKS_CONTEXT}" >/dev/null 2>&1 || true
  fi
}

verify_kubecontext() {
  # A context that does not exist (rename failed) or a config the invoking user
  # cannot read used to burn the whole NODE_APPEAR_TIMEOUT twice, invisibly.
  # Fail fast on the first one, with the real error, and prove the API answers.
  if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx "${EKS_CONTEXT}"; then
    echo "ERROR: kubecontext '${EKS_CONTEXT}' not present after update-kubeconfig" >&2
    diagnose_kubectl
    return 1
  fi
  if ! kubectl --context "${EKS_CONTEXT}" get nodes --request-timeout=10s >/dev/null; then
    echo "ERROR: context '${EKS_CONTEXT}' exists but its API is not reachable" >&2
    diagnose_kubectl
    return 1
  fi
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
      diagnose_node_failure
      return 1
    }
    if kubectl --context "${EKS_CONTEXT}" get nodes --no-headers 2>/dev/null | grep -q ' Ready '; then
      kubectl --context "${EKS_CONTEXT}" get nodes -o wide
      return 0
    fi
    sleep 5
  done
}

nodes_exist() {
  # True once the API server knows at least one Node object, whatever its state
  # (a node that exists but is NotReady is progress; an empty list means the k3s
  # node container never registered).
  kubectl --context "${EKS_CONTEXT}" get nodes --no-headers 2>/dev/null | grep -q .
}

wait_for_first_node() {
  # ACTIVE is not "the node is coming": Floci registers the cluster before the
  # k3s container is up, and a create cut off server-side can leave the row
  # ACTIVE with no node ever. Give the node a short window to appear so a
  # broken-but-ACTIVE cluster is caught fast instead of burning NODE_TIMEOUT.
  echo "── eks: waiting for the first node object (timeout ${NODE_APPEAR_TIMEOUT}s)"
  local deadline now
  deadline=$(( $(date +%s) + NODE_APPEAR_TIMEOUT ))
  while : ; do
    if nodes_exist; then
      return 0
    fi
    now="$(date +%s)"
    [ "${now}" -lt "${deadline}" ] || return 1
    sleep 5
  done
}

delete_cluster() {
  echo "── eks: deleting cluster '${EKS_CLUSTER}' (before recreate)"
  aws_cli eks delete-cluster --name "${EKS_CLUSTER}" >/dev/null 2>&1 || true
  # Converge on ABSENT so the recreate is not answered with ResourceInUse.
  local deadline now
  deadline=$(( $(date +%s) + NODE_APPEAR_TIMEOUT ))
  while : ; do
    [ "$(cluster_status)" = "ABSENT" ] && return 0
    now="$(date +%s)"
    [ "${now}" -lt "${deadline}" ] || {
      echo "  cluster still not ABSENT after ${NODE_APPEAR_TIMEOUT}s; proceeding to recreate anyway" >&2
      return 0
    }
    sleep 5
  done
}

diagnose_node_failure() {
  # A node that never appears is a substrate fault, not a platform one: dump the
  # emulator's logs and the Docker container list so the k3s node (and whether
  # Floci dropped it as stale) is visible in the uploaded artifacts.
  echo "── eks: collecting node-failure diagnostics into ${DIAGNOSE_DIR}/" >&2
  mkdir -p "${DIAGNOSE_DIR}"
  # kubectl's own view first: with the node waits silencing its stderr, a
  # client-side failure was invisible in the uploaded artifacts.
  diagnose_kubectl
  docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' \
    > "${DIAGNOSE_DIR}/eks-node-failure.containers.txt" 2>&1 || true
  docker logs "${FLOCI_NAME}" > "${DIAGNOSE_DIR}/eks-node-failure.floci.log" 2>&1 || true
  # K3s node containers Floci spawns carry the cluster name in their name/image;
  # dump their logs too when present.
  docker ps -a --format '{{.Names}}' 2>/dev/null | grep -iE 'k3s|sca-eks' | while read -r c; do
    [ -n "$c" ] || continue
    docker logs "$c" >> "${DIAGNOSE_DIR}/eks-node-failure.k3s.log" 2>&1 || true
  done || true
  echo "  wrote eks-node-failure.* into ${DIAGNOSE_DIR}/" >&2
}

create_cluster() {
  # One `create-cluster` request, no client retries: Floci's create is not
  # idempotent while it provisions — the handler blocks on the k3s container and
  # registers the cluster only once it is up, so an AWS-CLI retry past its (~5s)
  # client-side window provisions a *second* k3s container (the first later
  # dropped as stale), or the retry answers ResourceInUseException for the very
  # cluster it just registered (the original CI failure). The create verdict is
  # not a source of truth — converge on the cluster state instead.
  echo "── eks: creating cluster '${EKS_CLUSTER}' (role ${EKS_ROLE_ARN})"
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
}

fetch_kubeconfig() {
  echo "── eks: fetching kubeconfig (context ${EKS_CONTEXT})"
  ensure_kube_dir
  # `--alias` names the context (and makes it current) from inside the
  # container, so no host-side write is needed to get the stable name.
  aws_cli eks update-kubeconfig --name "${EKS_CLUSTER}" --alias "${EKS_CONTEXT}" \
    --kubeconfig /root/.kube/config --endpoint-url "${ENDPOINT}" >/dev/null
  kubeconfig_ownership
  rename_context
  verify_kubecontext
}

eks_up() {
  echo "── eks: starting cloud emulator on network '${CLOUD_NETWORK}' (EKS mode)"
  CLOUD_NETWORK="${CLOUD_NETWORK}" "${SELF_DIR}/cloud-emulator.sh" start "${CLOUD_PROVIDER:-aws}"
  wait_for_api

  ensure_iam_admin

  local status recreate=1
  status="$(cluster_status)"
  if [ "${status}" = "ACTIVE" ]; then
    echo "[skip] EKS cluster '${EKS_CLUSTER}' already ACTIVE"
  elif [ "${status}" = "ABSENT" ] || [ "${status}" = "UNKNOWN" ]; then
    create_cluster
    wait_for_cluster_active
  else
    echo "  cluster '${EKS_CLUSTER}' already present (status ${status}); waiting for ACTIVE"
    wait_for_cluster_active
  fi

  fetch_kubeconfig

  # ACTIVE does not mean the node came up: Floci records the cluster row before
  # the k3s node registers, and a create cut off server-side (the observed CI
  # failure — `Connection was closed before we received a valid response`) leaves
  # that row ACTIVE with no node ever appearing, burning the full NODE_TIMEOUT.
  # Catch it fast and recreate the cluster once before giving up.
  while ! wait_for_first_node; do
    if [ "${recreate}" -eq 0 ]; then
      echo "ERROR: cluster '${EKS_CLUSTER}' reported ACTIVE but no node appeared after a recreate" >&2
      diagnose_node_failure
      return 1
    fi
    echo "  cluster ACTIVE but no node appeared within ${NODE_APPEAR_TIMEOUT}s; recreating once" >&2
    diagnose_node_failure
    delete_cluster
    create_cluster
    wait_for_cluster_active
    fetch_kubeconfig
    recreate=0
  done

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
