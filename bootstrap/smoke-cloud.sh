#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-cloud.sh — run the cloud-integration smoke for the active provider
# against a live cluster. Each provider ships its own check under
# bootstrap/smoke-cloud-<provider>.sh; the emulator itself is a prerequisite
# brought up by bootstrap/cloud-emulator.sh.
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

provider="${1:-${CLOUD_PROVIDER:-aws}}"
case "$provider" in
  aws) exec "$(dirname "$0")/smoke-cloud-aws.sh" ;;
  "") echo "usage: $0 <provider> (aws)" >&2; exit 2 ;;
  *) echo "ERROR: no cloud smoke command for provider '$provider' (known: aws)" >&2; exit 2 ;;
esac
