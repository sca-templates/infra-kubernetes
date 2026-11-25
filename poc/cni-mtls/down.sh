#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_tools docker

docker rm --force "${CNI_MTLS_SERVER_NAME}" >/dev/null 2>&1 || true
docker rm --force "${CNI_MTLS_AGENT_NAME}" >/dev/null 2>&1 || true
docker network rm "${CNI_MTLS_NETWORK}" >/dev/null 2>&1 || true
rm -rf "${CNI_MTLS_GENERATED_DIR}"

echo "CNI_MTLS_POC_DOWN_OK"
