#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# cloud-emulator.sh — provider-agnostic local cloud-emulator lifecycle for the
# cluster smoke (docs/ci-cd.md). Runs the emulator as a Docker container on the
# host/runner and publishes it into the cluster through a selector-less Service
# + EndpointSlice in the `cloud` namespace, so in-cluster pods reach a stable
# endpoint without a cloud account, IAM material or per-cloud configuration.
#
# Providers: `aws` (Floci). Adding a cloud means adding a provider case here
# and a matching bootstrap/smoke-cloud-<provider>.sh — nothing else.
#
# Usage:
#   cloud-emulator.sh up       [provider]   # start + publish into the cluster
#   cloud-emulator.sh start    [provider]   # start the container only
#   cloud-emulator.sh publish  [provider]   # publish into the current cluster
#   cloud-emulator.sh down     [provider]
#   cloud-emulator.sh status   [provider]
#
# Env: CLOUD_PROVIDER (default aws), FLOCI_IMAGE / FLOCI_PORT (from
#      bootstrap/versions.sh and .env), CLOUD_NAMESPACE (cloud),
#      CLOUD_NETWORK (explicit Docker network; default FLOCI_EKS_NETWORK).
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

ACTION="${1:-}"
PROVIDER="${2:-${CLOUD_PROVIDER:-aws}}"

CLOUD_NAMESPACE="${CLOUD_NAMESPACE:-cloud}"
FLOCI_NAME="${FLOCI_NAME:-floci}"
FLOCI_PORT="${FLOCI_PORT:-4566}"
STATE_DIR=".generated"
# Docker network the emulator joins and is published on. The EKS substrate
# (bootstrap/eks-emulator.sh) passes the network its k3s node joins; standalone
# `make cloud-up` defaults to the same network coordinates.
CLOUD_NETWORK="${CLOUD_NETWORK:-${FLOCI_EKS_NETWORK:-sca-eks}}"

[ -n "$ACTION" ] || { echo "usage: $0 up|start|publish|down|status [provider]" >&2; exit 2; }

# ── aws (Floci) ──────────────────────────────────────────────────────────────

wait_for_edge() {
  # TCP reachability on the host's published port; /dev/tcp keeps us from
  # depending on curl/wget being installed on the runner.
  local port="$1" timeout="${2:-60}" i=0
  while ! (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge "$timeout" ]; then
      echo "ERROR: cloud emulator did not listen on :${port} within ${timeout}s" >&2
      return 1
    fi
    sleep 1
  done
  echo "  edge listening on 127.0.0.1:${port} (attempt ${i})"
}

aws_start() {
  echo "── cloud(${PROVIDER}): starting ${FLOCI_NAME} (${FLOCI_IMAGE})"
  docker rm -f "${FLOCI_NAME}" >/dev/null 2>&1 || true

  # EKS mode: attach the emulator to a dedicated, named Docker network and tell
  # Floci to spawn its k3s node onto the same network (FLOCI_SERVICES_DOCKER_
  # NETWORK) with the ECR registry mirror injected into the node's containerd
  # (FLOCI_SERVICES_EKS_ECR_REGISTRY_MIRROR), so the cluster can pull images
  # pushed to Floci's ECR.
  #
  # FLOCI_SERVICES_EKS_DEFAULT_STORAGE_CLASS keeps k3s's bundled local-path
  # provisioner + default StorageClass: Floci disables both by default to match
  # real EKS (no default class without a CSI driver), which leaves every PVC on
  # the smoke cluster Pending (vault dataStorage). All three are harmless
  # outside EKS.
  docker network inspect "${CLOUD_NETWORK}" >/dev/null 2>&1 \
    || docker network create "${CLOUD_NETWORK}" >/dev/null
  local run_args=(
    --network "${CLOUD_NETWORK}"
    -e FLOCI_SERVICES_DOCKER_NETWORK="${CLOUD_NETWORK}"
    -e FLOCI_SERVICES_EKS_ECR_REGISTRY_MIRROR=true
    -e FLOCI_SERVICES_EKS_DEFAULT_STORAGE_CLASS=true
  )

  docker run -d --name "${FLOCI_NAME}" \
    -p "${FLOCI_PORT}:${FLOCI_PORT}" \
    "${run_args[@]}" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "${FLOCI_IMAGE}" >/dev/null
  wait_for_edge "${FLOCI_PORT}"
}

resolve_network() {
  # Print the Docker network the emulator is published on: CLOUD_NETWORK when
  # set, otherwise the EKS substrate network the k3s node joins.
  printf '%s' "${CLOUD_NETWORK}"
}

aws_publish() {
  local network ip
  network="$(resolve_network)" || return 1
  if ! docker inspect "${FLOCI_NAME}" \
      --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' \
      | grep -qx "$network"; then
    docker network connect "$network" "${FLOCI_NAME}"
  fi
  ip="$(docker inspect "${FLOCI_NAME}" \
    --format "{{(index .NetworkSettings.Networks \"${network}\").IPAddress}}")"
  [ -n "$ip" ] || { echo "ERROR: ${FLOCI_NAME} has no IP on network '${network}'" >&2; return 1; }
  echo "  published on docker network '${network}' as ${ip}:${FLOCI_PORT}"

  echo "── cloud(${PROVIDER}): publishing Service/${FLOCI_NAME} in ns ${CLOUD_NAMESPACE}"
  mkdir -p "${STATE_DIR}"
  kubectl create namespace "${CLOUD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  # Drop any legacy v1 Endpoints left by an earlier revision: an Endpoints
  # object here would only produce a mirrored, redundant EndpointSlice.
  kubectl -n "${CLOUD_NAMESPACE}" delete endpoints "${FLOCI_NAME}" --ignore-not-found >/dev/null 2>&1 || true
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${FLOCI_NAME}
  namespace: ${CLOUD_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${FLOCI_NAME}
    app.kubernetes.io/part-of: sca-cloud-smoke
    app.kubernetes.io/managed-by: cloud-emulator.sh
spec:
  type: ClusterIP
  ports:
    - name: edge
      port: ${FLOCI_PORT}
      targetPort: ${FLOCI_PORT}
      protocol: TCP
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: ${FLOCI_NAME}
  namespace: ${CLOUD_NAMESPACE}
  labels:
    kubernetes.io/service-name: ${FLOCI_NAME}
    app.kubernetes.io/name: ${FLOCI_NAME}
    app.kubernetes.io/part-of: sca-cloud-smoke
    app.kubernetes.io/managed-by: cloud-emulator.sh
addressType: IPv4
endpoints:
  - addresses:
      - ${ip}
ports:
  - name: edge
    port: ${FLOCI_PORT}
    protocol: TCP
EOF
  kubectl -n "${CLOUD_NAMESPACE}" get svc "${FLOCI_NAME}" \
    -o custom-columns=NAME:.metadata.name,CLUSTER-IP:.spec.clusterIP >/dev/null
  kubectl -n "${CLOUD_NAMESPACE}" get endpointslice "${FLOCI_NAME}" >/dev/null
  echo "  in-cluster endpoint: http://${FLOCI_NAME}.${CLOUD_NAMESPACE}.svc.cluster.local:${FLOCI_PORT}"
}

aws_up() {
  aws_start
  aws_publish
}

aws_down() {
  echo "── cloud(${PROVIDER}): tearing down"
  kubectl delete namespace "${CLOUD_NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true
  docker rm -f "${FLOCI_NAME}" >/dev/null 2>&1 || true
  echo "  Service/${CLOUD_NAMESPACE}/${FLOCI_NAME} and container '${FLOCI_NAME}' removed"
}

aws_status() {
  echo "── cloud(${PROVIDER}): container '${FLOCI_NAME}'"
  local state
  # `docker inspect -f` prints the (empty) rendered template to stdout and
  # exits non-zero when the container is absent, so scrub the whitespace and
  # fall back to `absent` ourselves.
  state="$(docker inspect -f '{{.State.Status}}' "${FLOCI_NAME}" 2>/dev/null || true)"
  state="$(printf '%s' "$state" | tr -d '[:space:]')"
  state="${state:-absent}"
  echo "  docker: ${state}"
  if [ "$state" = "running" ]; then
    if (exec 3<>"/dev/tcp/127.0.0.1/${FLOCI_PORT}") 2>/dev/null; then
      echo "  edge: reachable on 127.0.0.1:${FLOCI_PORT}"
    else
      echo "  edge: NOT reachable on 127.0.0.1:${FLOCI_PORT}" >&2
      return 1
    fi
  fi
  echo "── cloud(${PROVIDER}): in-cluster Service"
  kubectl -n "${CLOUD_NAMESPACE}" get svc "${FLOCI_NAME}" 2>/dev/null || {
    echo "  Service/${FLOCI_NAME} not present in ns ${CLOUD_NAMESPACE}" >&2
    return 1
  }
}

# ── dispatch ────────────────────────────────────────────────────────────────

case "$ACTION" in
  up)
    case "$PROVIDER" in
      aws) aws_up ;;
      *) echo "ERROR: no cloud-emulator provider '$PROVIDER' (known: aws)" >&2; exit 2 ;;
    esac
    ;;
  start)
    case "$PROVIDER" in
      aws) aws_start ;;
      *) echo "ERROR: no cloud-emulator provider '$PROVIDER' (known: aws)" >&2; exit 2 ;;
    esac
    ;;
  publish)
    case "$PROVIDER" in
      aws) aws_publish ;;
      *) echo "ERROR: no cloud-emulator provider '$PROVIDER' (known: aws)" >&2; exit 2 ;;
    esac
    ;;
  down)
    case "$PROVIDER" in
      aws) aws_down ;;
      *) echo "ERROR: no cloud-emulator provider '$PROVIDER' (known: aws)" >&2; exit 2 ;;
    esac
    ;;
  status)
    case "$PROVIDER" in
      aws) aws_status ;;
      *) echo "ERROR: no cloud-emulator provider '$PROVIDER' (known: aws)" >&2; exit 2 ;;
    esac
    ;;
  *)
    echo "usage: $0 up|start|publish|down|status [provider]" >&2
    exit 2
    ;;
esac
