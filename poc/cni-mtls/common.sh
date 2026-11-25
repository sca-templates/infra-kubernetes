#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
set -euo pipefail

COMMON_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${COMMON_DIR}/../.." && pwd)"

source "${COMMON_DIR}/versions.env"

CNI_MTLS_NETWORK="${CNI_MTLS_NETWORK:-cni-mtls-poc}"
CNI_MTLS_SUBNET="${CNI_MTLS_SUBNET:-172.30.0.0/16}"
CNI_MTLS_SERVER_NAME="${CNI_MTLS_SERVER_NAME:-cni-mtls-server}"
CNI_MTLS_AGENT_NAME="${CNI_MTLS_AGENT_NAME:-cni-mtls-agent-1}"
CNI_MTLS_SERVER_IP="${CNI_MTLS_SERVER_IP:-172.30.0.10}"
CNI_MTLS_AGENT_IP="${CNI_MTLS_AGENT_IP:-172.30.0.11}"
CNI_MTLS_API_PORT="${CNI_MTLS_API_PORT:-16443}"
CNI_MTLS_GENERATED_DIR="${CNI_MTLS_GENERATED_DIR:-${REPO_ROOT}/.generated/cni-mtls}"
CNI_MTLS_SERVER_KUBECONFIG="${CNI_MTLS_GENERATED_DIR}/server-kubeconfig.yaml"
CNI_MTLS_KUBECONFIG_PATH="${CNI_MTLS_KUBECONFIG_PATH:-${CNI_MTLS_GENERATED_DIR}/kubeconfig}"
CNI_MTLS_TOKEN_PATH="${CNI_MTLS_GENERATED_DIR}/cluster-token"

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "${tool}" >/dev/null 2>&1 || { echo "ERROR: ${tool} is required"; exit 1; }
  done
}

kube() {
  kubectl --kubeconfig "${CNI_MTLS_KUBECONFIG_PATH}" "$@"
}
