#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_tools docker

docker rm --force "${CALICO_WG_SERVER_NAME}" >/dev/null 2>&1 || true
docker rm --force "${CALICO_WG_AGENT_NAME}" >/dev/null 2>&1 || true
docker network rm "${CALICO_WG_NETWORK}" >/dev/null 2>&1 || true
rm -rf "${CALICO_WG_GENERATED_DIR}"

echo "CALICO_WG_POC_DOWN_OK"
