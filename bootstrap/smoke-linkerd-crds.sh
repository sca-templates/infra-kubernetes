#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-linkerd-crds.sh — verify the linkerd-crds chart's CRDs are present and
# Established (the project gate: "linkerd CRDs present in the cluster and
# alive"). The component is CRD-only (no workloads), so the smoke's assertions
# are the real readiness: namespace `linkerd` exists (appset destination +
# CreateNamespace), every expected CRD of the linkerd.io / policy.linkerd.io
# groups is Established, and the chart-default Gateway API HTTPRoute CRD is
# present. Selective smoke for the linkerd-crds component; driven by
# `make smoke COMPONENT=linkerd-crds` (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${LINKERD_NS:-linkerd}"
TIMEOUT="${SMOKE_TIMEOUT:-120s}"

# CRD set shipped by linkerd/linkerd-crds chart 1.8.0 (helm.linkerd.io/stable).
EXPECTED_CRDS=(
  serviceprofiles.linkerd.io
  servers.policy.linkerd.io
  serverauthorizations.policy.linkerd.io
  authorizationpolicies.policy.linkerd.io
  meshtlsauthentications.policy.linkerd.io
  networkauthentications.policy.linkerd.io
  httproutes.policy.linkerd.io
  httproutes.gateway.networking.k8s.io
)

echo "── smoke(linkerd-crds): namespace ${NAMESPACE} present"
kubectl get namespace "$NAMESPACE" --no-headers >/dev/null

echo "── smoke(linkerd-crds): ${EXPECTED_CRDS[*]}"
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
  echo "FAIL: one or more linkerd CRDs are missing (above)" >&2
  exit 1
}

echo "── smoke(linkerd-crds): control-plane CRDs ready for Phase 9"
kubectl get crd -l 'linkerd.io/control-plane-ns=='"${NAMESPACE}" --no-headers

echo "[OK] smoke(linkerd-crds): linkerd CRDs present and Established"