#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-nack.sh — verify the NACK JetStream controller is deployed with its CRDs
# Established and a cluster-wide watch. NACK (the NATS Controller for
# Kubernetes) installs the `streams`, `consumers`, `streamtemplates`,
# `accounts`, `keyvalues` and `objectstores` CRDs and reconciles `Stream`/
# `Consumer` CRs into the NATS server. No CR ships in git: NATS is deployed
# "ready but idle" (ADR-005), so the smoke asserts the controller is Ready and
# the CRDs exist — the first `Stream` arrives with the consumer wiring, not
# before.
# Selective smoke for the nack component; driven by
# `make smoke COMPONENT=nack` (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${NACK_NS:-nats}"
DEPLOYMENT="${NACK_DEPLOYMENT:-nack}"
TIMEOUT="${SMOKE_TIMEOUT:-120s}"

# CRD set shipped by the nats/nack chart 0.35.0 (appVersion 0.24.0), all in the
# `jetstream.nats.io` group.
EXPECTED_CRDS=(
  streams.jetstream.nats.io
  consumers.jetstream.nats.io
  streamtemplates.jetstream.nats.io
  accounts.jetstream.nats.io
  keyvalues.jetstream.nats.io
  objectstores.jetstream.nats.io
)

echo "── smoke(nack): namespace ${NAMESPACE} present"
kubectl get namespace "$NAMESPACE" --no-headers >/dev/null

echo "── smoke(nack): deployment ${NAMESPACE}/${DEPLOYMENT} Ready"
kubectl -n "$NAMESPACE" rollout status "deployment/${DEPLOYMENT}" --timeout="$TIMEOUT" >/dev/null

# The controller must watch every namespace: `Stream`/`Consumer` CRs land in
# `data` (the NATS server's namespace), not in the controller's own `nats`.
# `namespaced: false` (the chart default) renders no `--namespace` arg — the
# chart's way of saying "cluster-wide", the mirror image of redis-operator's
# unset WATCH_NAMESPACE.
echo "── smoke(nack): controller watches all namespaces (Stream/Consumer CRs land in data)"
args="$(kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" \
  -o jsonpath='{.spec.template.spec.containers[0].args[*]}')"
if printf '%s' "$args" | grep -q -- '--namespace='; then
  echo "FAIL: controller is namespaced (args contain --namespace=): ${args}" >&2
  exit 1
fi
echo "  no --namespace arg (watches every namespace)"

echo "── smoke(nack): ${EXPECTED_CRDS[*]}"
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
  echo "FAIL: one or more nack CRDs are missing (above)" >&2
  exit 1
}

echo "[OK] smoke(nack): controller Ready, 6 jetstream.nats.io CRDs Established, cluster-wide watch"
