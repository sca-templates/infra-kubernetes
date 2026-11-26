#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-target.sh — run the smoke command for a component against a live cluster.
# Usage: bootstrap/smoke-target.sh <component>
# Each component ships its own check under bootstrap/smoke-<component>.sh.
set -euo pipefail

component="${1:-}"
case "$component" in
  cni) exec "$(dirname "$0")/smoke-cni.sh" ;;
  cert-manager) exec "$(dirname "$0")/smoke-cert-manager.sh" ;;
  vault) exec "$(dirname "$0")/smoke-vault.sh" ;;
  external-secrets) exec "$(dirname "$0")/smoke-external-secrets.sh" ;;
  cloudnative-pg) exec "$(dirname "$0")/smoke-cloudnative-pg.sh" ;;
  plugin-barman-cloud) exec "$(dirname "$0")/smoke-plugin-barman-cloud.sh" ;;
  postgres-app) exec "$(dirname "$0")/smoke-postgres-app.sh" ;;
  redis-operator) exec "$(dirname "$0")/smoke-redis-operator.sh" ;;
  redis) exec "$(dirname "$0")/smoke-redis.sh" ;;
  nack) exec "$(dirname "$0")/smoke-nack.sh" ;;
  nats) exec "$(dirname "$0")/smoke-nats.sh" ;;
  kong) exec "$(dirname "$0")/smoke-kong.sh" ;;
  zitadel) exec "$(dirname "$0")/smoke-zitadel.sh" ;;
  velero) exec "$(dirname "$0")/smoke-velero.sh" ;;
  cloud) exec "$(dirname "$0")/smoke-cloud.sh" ;;
  eks) exec "$(dirname "$0")/smoke-eks.sh" ;;
  "") echo "usage: $0 <component> (cni, cert-manager, vault, external-secrets, cloudnative-pg, plugin-barman-cloud, postgres-app, redis-operator, kong, redis, nack, nats, zitadel, velero, cloud, eks)" >&2; exit 2 ;;
  *,*) echo "ERROR: smoke-target.sh smokes one component; use smoke-ci.sh for a comma-separated list" >&2; exit 2 ;;
  *) echo "ERROR: no smoke command for component '$component'" >&2; exit 2 ;;
esac
