#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-strimzi.sh — verify the Strimzi operator is deployed and its CRDs are
# present and Established (the project gate: "operator pod Running, Kafka CR
# groups present"). Readiness = Deployment available (the CRDs must be served
# before any Kafka CR can be applied) + every `kafka.strimzi.io` /
# `core.strimzi.io` CRD Established. No `Kafka`/`KafkaNodePool` CR exists yet:
# the event backbone arrives as raw CRs in `data` at Phase 11. Selective smoke
# for the strimzi component; driven by `make smoke COMPONENT=strimzi`
# (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${STRIMZI_NS:-strimzi}"
DEPLOYMENT="${STRIMZI_DEPLOYMENT:-strimzi-cluster-operator}"
TIMEOUT="${SMOKE_TIMEOUT:-120s}"

# CRD set shipped by strimzi/strimzi-kafka-operator chart 1.2.0: nine
# `kafka.strimzi.io` CRDs plus the internal `core.strimzi.io` StrimziPodSet
# that the operator uses to render broker StatefulSets.
EXPECTED_CRDS=(
  kafkaconnects.kafka.strimzi.io
  kafkabridges.kafka.strimzi.io
  kafkaconnectors.kafka.strimzi.io
  kafkamirrormaker2s.kafka.strimzi.io
  kafkanodepools.kafka.strimzi.io
  kafkarebalances.kafka.strimzi.io
  kafkas.kafka.strimzi.io
  kafkatopics.kafka.strimzi.io
  kafkausers.kafka.strimzi.io
  strimzipodsets.core.strimzi.io
)

echo "── smoke(strimzi): namespace ${NAMESPACE} present"
kubectl get namespace "$NAMESPACE" --no-headers >/dev/null

echo "── smoke(strimzi): deployment ${NAMESPACE}/${DEPLOYMENT} Ready"
kubectl -n "$NAMESPACE" rollout status "deployment/${DEPLOYMENT}" --timeout="$TIMEOUT" >/dev/null

echo "── smoke(strimzi): operator watches all namespaces (Kafka CRs land in data at Phase 11)"
watch_all="$(kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="STRIMZI_NAMESPACE")].value}')"
if [ "$watch_all" != "*" ]; then
  echo "FAIL: STRIMZI_NAMESPACE='${watch_all}', expected '*' (watchAnyNamespace)" >&2
  exit 1
fi
echo "  STRIMZI_NAMESPACE=*"

echo "── smoke(strimzi): ${EXPECTED_CRDS[*]}"
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
  echo "FAIL: one or more Strimzi CRDs are missing (above)" >&2
  exit 1
}

echo "[OK] smoke(strimzi): operator Ready, kafka/core.strimzi.io CRDs Established"
