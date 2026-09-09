#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-cloudnative-pg.sh — verify the CloudNativePG operator is deployed and
# its CRDs are present and Established (the project gate: "operator pod
# Running, CNPG CRD groups present"). Readiness = Deployment available (the
# webhooks depend on the operator pod) + every `postgresql.cnpg.io` CRD
# Established. No `Cluster` CR exists yet: the datastores (postgres-app,
# keycloak-db) arrive as raw CRs at Phase 10. Selective smoke for the
# cloudnative-pg component; driven by `make smoke COMPONENT=cloudnative-pg`
# (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${CLOUDNATIVEPG_NS:-cloudnative-pg}"
DEPLOYMENT="${CLOUDNATIVEPG_DEPLOYMENT:-cloudnative-pg}"
TIMEOUT="${SMOKE_TIMEOUT:-120s}"

# CRD set shipped by cloudnative-pg/cloudnative-pg chart 0.29.0
# (postgresql.cnpg.io group).
EXPECTED_CRDS=(
  backups.postgresql.cnpg.io
  clusterimagecatalogs.postgresql.cnpg.io
  clusters.postgresql.cnpg.io
  databaseroles.postgresql.cnpg.io
  databases.postgresql.cnpg.io
  failoverquorums.postgresql.cnpg.io
  imagecatalogs.postgresql.cnpg.io
  poolers.postgresql.cnpg.io
  publications.postgresql.cnpg.io
  scheduledbackups.postgresql.cnpg.io
  subscriptions.postgresql.cnpg.io
)

echo "── smoke(cloudnative-pg): namespace ${NAMESPACE} present"
kubectl get namespace "$NAMESPACE" --no-headers >/dev/null

echo "── smoke(cloudnative-pg): deployment ${NAMESPACE}/${DEPLOYMENT} Ready"
kubectl -n "$NAMESPACE" rollout status "deployment/${DEPLOYMENT}" --timeout="$TIMEOUT" >/dev/null

echo "── smoke(cloudnative-pg): ${EXPECTED_CRDS[*]}"
missing=0
for crd in "${EXPECTED_CRDS[@]}"; do
  if ! kubectl get crd "$crd" --no-headers >/dev/null 2>&1; then
    echo "FAIL: CRD ${crd} is missing" >&2
    missing=1
    continue
  fi
  kubectl wait --for=condition=Established "crd/${crd}" --timeout="$TIMEOUT" >/dev/null
  echo "  ${crd} → Established"
done

[ "$missing" -eq 0 ] || {
  echo "FAIL: one or more CNPG CRDs are missing (above)" >&2
  exit 1
}

echo "[OK] smoke(cloudnative-pg): operator Ready, postgresql.cnpg.io CRDs Established"