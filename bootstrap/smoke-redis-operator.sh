#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-redis-operator.sh — verify the Redis operator is deployed, its CRDs are
# present and Established, and a throwaway `Redis` CR is actually honored
# (StatefulSet Ready, pod Running, `redis-cli PING` → PONG). The project gate:
# "operator pod Running, Redis CR group present" plus the roadmap's project-done
# clause "a `Redis` CR review shows the CR is honored". No `Redis` CR ships in
# git: the cache lands as a real CR in `data` at Phase 12 (wave 40).
# Selective smoke for the redis-operator component; driven by
# `make smoke COMPONENT=redis-operator` (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${REDIS_OPERATOR_NS:-data}"
DEPLOYMENT="${REDIS_OPERATOR_DEPLOYMENT:-redis-operator}"
SCRATCH_NS="redis-operator-smoke"
SCRATCH_CR="smoke-redis"
TIMEOUT="${SMOKE_TIMEOUT:-120s}"
STS_TIMEOUT="${REDIS_STS_TIMEOUT:-300}"
POLL="${REDIS_POLL:-5}"
# Pinned Redis image for the throwaway CR. Upstream's own example ships
# `quay.io/opstree/redis:latest`, which the repo's pinned-tags policy forbids;
# the CR must therefore always name an explicit tag. v7.4 is the Redis 7 line the
# Compose counterpart (infra-redis) runs.
REDIS_IMAGE="${REDIS_IMAGE:-quay.io/opstree/redis:v7.4.11}"

# CRD set shipped by ot-container-kit/redis-operator chart 0.26.1: the standalone
# `Redis` CR plus the three grouped topologies Phase 12 can choose from
# (`RedisCluster`, `RedisReplication` + `RedisSentinel`), all in the
# `redis.redis.opstreelabs.in` group.
EXPECTED_CRDS=(
  redis.redis.redis.opstreelabs.in
  redisclusters.redis.redis.opstreelabs.in
  redisreplications.redis.redis.opstreelabs.in
  redissentinels.redis.redis.opstreelabs.in
)

cleanup() {
  kubectl delete namespace "$SCRATCH_NS" --ignore-not-found 2>/dev/null || true
}
trap cleanup EXIT

echo "── smoke(redis-operator): namespace ${NAMESPACE} present"
kubectl get namespace "$NAMESPACE" --no-headers >/dev/null

echo "── smoke(redis-operator): deployment ${NAMESPACE}/${DEPLOYMENT} Ready"
kubectl -n "$NAMESPACE" rollout status "deployment/${DEPLOYMENT}" --timeout="$TIMEOUT" >/dev/null

# The operator must watch the CRs wherever they land: the Redis datastores run in
# `data` (Phase 12), not in the operator's own namespace. An empty
# `redisOperator.watchNamespace` renders no WATCH_NAMESPACE env at all, which is
# the chart's way of saying "all namespaces" — the mirror image of Strimzi's
# explicit `STRIMZI_NAMESPACE=*`.
echo "── smoke(redis-operator): operator watches all namespaces (Redis CRs land in data at Phase 12)"
watch_all="$(kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="WATCH_NAMESPACE")].value}')"
if [ -n "$watch_all" ] && [ "$watch_all" != "*" ]; then
  echo "FAIL: WATCH_NAMESPACE='${watch_all}', expected unset or '*' (cluster-wide watch)" >&2
  exit 1
fi
echo "  WATCH_NAMESPACE unset (watches every namespace)"

echo "── smoke(redis-operator): ${EXPECTED_CRDS[*]}"
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
  echo "FAIL: one or more redis-operator CRDs are missing (above)" >&2
  exit 1
}

# A `Redis` CR writes no status conditions (its CRD declares an empty status
# object), so "the CR is honored" has to be proven from the objects the operator
# creates: for a standalone `Redis` CR the StatefulSet and Services take the CR's
# own name (plus `-headless`). `redisExporter` is omitted on purpose — the CRD
# requires an image whenever the block is present, and a second pod would mean a
# second image pin for a throwaway. The throwaway lives in its own scratch
# namespace, never in `data`, and the trap above removes it — the real cache
# arrives with Phase 12.
echo "── smoke(redis-operator): throwaway Redis CR ${SCRATCH_NS}/${SCRATCH_CR} is honored"
kubectl create namespace "$SCRATCH_NS" >/dev/null
kubectl -n "$SCRATCH_NS" apply -f - <<EOF
apiVersion: redis.redis.opstreelabs.in/v1beta2
kind: Redis
metadata:
  name: ${SCRATCH_CR}
spec:
  kubernetesConfig:
    image: ${REDIS_IMAGE}
    imagePullPolicy: IfNotPresent
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 128Mi
EOF

sts_ready() {
  [ "$(kubectl -n "$SCRATCH_NS" get statefulset "$SCRATCH_CR" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)" = "1" ]
}
echo "── smoke(redis-operator): waiting for statefulset/${SCRATCH_CR} ready"
for attempt in $(seq 1 "$STS_TIMEOUT"); do
  sts_ready && { echo "  statefulset/${SCRATCH_CR} readyReplicas=1 (attempt ${attempt})"; break; }
  [ "$attempt" -eq "$STS_TIMEOUT" ] && {
    echo "FAIL: statefulset/${SCRATCH_CR} never became ready (CR not honored)" >&2
    kubectl -n "$SCRATCH_NS" get redis,statefulset,pods -o wide >&2 2>/dev/null || true
    exit 1
  }
  sleep "$POLL"
done

echo "── smoke(redis-operator): redis-cli PING via the throwaway pod"
ping="$(
  kubectl -n "$SCRATCH_NS" exec "$SCRATCH_CR-0" -- \
    redis-cli --no-auth-warning PING 2>/dev/null || true
)"
if [ "$ping" != "PONG" ]; then
  echo "FAIL: PING returned '${ping:-<empty>}', expected 'PONG'" >&2
  kubectl -n "$SCRATCH_NS" describe statefulset "$SCRATCH_CR" >&2 2>/dev/null || true
  kubectl -n "$SCRATCH_NS" logs "$SCRATCH_CR-0" --tail=50 >&2 2>/dev/null || true
  exit 1
fi
echo "  PING → PONG"

echo "[OK] smoke(redis-operator): operator Ready, 4 redis.redis.opstreelabs.in CRDs Established, Redis CR honored (PING → PONG)"
