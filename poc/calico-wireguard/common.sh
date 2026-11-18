#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
set -euo pipefail

COMMON_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${COMMON_DIR}/../.." && pwd)"

source "${COMMON_DIR}/versions.env"

CALICO_WG_NETWORK="${CALICO_WG_NETWORK:-calico-wg-poc}"
CALICO_WG_SUBNET="${CALICO_WG_SUBNET:-172.30.0.0/16}"
CALICO_WG_SERVER_NAME="${CALICO_WG_SERVER_NAME:-calico-wg-server}"
CALICO_WG_AGENT_NAME="${CALICO_WG_AGENT_NAME:-calico-wg-agent-1}"
CALICO_WG_SERVER_IP="${CALICO_WG_SERVER_IP:-172.30.0.10}"
CALICO_WG_AGENT_IP="${CALICO_WG_AGENT_IP:-172.30.0.11}"
CALICO_WG_API_PORT="${CALICO_WG_API_PORT:-16444}"
CALICO_WG_GENERATED_DIR="${CALICO_WG_GENERATED_DIR:-${REPO_ROOT}/.generated/calico-wireguard}"
CALICO_WG_SERVER_KUBECONFIG="${CALICO_WG_GENERATED_DIR}/server-kubeconfig.yaml"
CALICO_WG_KUBECONFIG_PATH="${CALICO_WG_KUBECONFIG_PATH:-${CALICO_WG_GENERATED_DIR}/kubeconfig}"
CALICO_WG_TOKEN_PATH="${CALICO_WG_GENERATED_DIR}/cluster-token"
CALICO_WG_MANIFEST_PATH="${CALICO_WG_GENERATED_DIR}/calico.yaml"

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "${tool}" >/dev/null 2>&1 || { echo "ERROR: ${tool} is required"; exit 1; }
  done
}

kube() {
  kubectl --kubeconfig "${CALICO_WG_KUBECONFIG_PATH}" "$@"
}
