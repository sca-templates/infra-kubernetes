#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-target.sh — run the smoke command for a component against a live cluster.
# Usage: bootstrap/smoke-target.sh <component>
# Each component ships its own check under bootstrap/smoke-<component>.sh.
set -euo pipefail

component="${1:-}"
case "$component" in
  cert-manager) exec "$(dirname "$0")/smoke-cert-manager.sh" ;;
  vault) exec "$(dirname "$0")/smoke-vault.sh" ;;
  external-secrets) exec "$(dirname "$0")/smoke-external-secrets.sh" ;;
  "") echo "usage: $0 <component> (cert-manager, vault, external-secrets)" >&2; exit 2 ;;
  *) echo "ERROR: no smoke command for component '$component'" >&2; exit 2 ;;
esac