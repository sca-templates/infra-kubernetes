#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-redis.sh — verify Phase 12 RedisReplication is ready and usable:
# the password is projected from Vault by ESO, the Redis pods are Ready, and
# a redis-cli client can PING, SET, GET and verify AOF persistence. In
# qa/prod the embedded Sentinel is present and reports the master via
# SENTINEL get-master-addr-by-name mymaster.
set -euo pipefail

NAMESPACE="${REDIS_NAMESPACE:-data}"
CR_NAME="${REDIS_CR_NAME:-redis}"
CREDENTIALS_SECRET="${REDIS_CREDENTIALS_SECRET:-redis-password}"
TIMEOUT="${SMOKE_TIMEOUT:-600s}"
MASTER_SERVICE="${REDIS_MASTER_SERVICE:-${CR_NAME}-master}"

POD=""
KEY=""

cleanup() {
  if [ -n "${POD}" ] && [ -n "${KEY}" ]; then
    kubectl -n "${NAMESPACE}" exec "${POD}" -- \
      env REDISCLI_AUTH="${PASSWORD}" redis-cli -h "${MASTER_SERVICE}" DEL "${KEY}" \
      >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

wait_externalsecret() {
  local name="$1" reason=""
  echo "── smoke(redis): ExternalSecret ${NAMESPACE}/${name} SecretSynced"
  for attempt in {1..120}; do
    reason="$(kubectl -n "${NAMESPACE}" get externalsecret "${name}" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || true)"
    [ "${reason}" = "SecretSynced" ] && return 0
    [ "${attempt}" -eq 120 ] && {
      echo "FAIL: ExternalSecret ${NAMESPACE}/${name} never reached SecretSynced (last: ${reason:-<none>})" >&2
      kubectl -n "${NAMESPACE}" get externalsecret "${name}" -o yaml >&2 2>/dev/null || true
      exit 1
    }
    sleep 5
  done
}

wait_statefulset() {
  local name="$1"
  echo "── smoke(redis): StatefulSet ${NAMESPACE}/${name} Ready"
  for attempt in {1..120}; do
    kubectl -n "${NAMESPACE}" get statefulset "${name}" >/dev/null 2>&1 && break
    [ "${attempt}" -eq 120 ] && {
      echo "FAIL: StatefulSet ${NAMESPACE}/${name} was never created" >&2
      exit 1
    }
    sleep 5
  done
  kubectl -n "${NAMESPACE}" rollout status "statefulset/${name}" --timeout="${TIMEOUT}"
}

wait_externalsecret "${CREDENTIALS_SECRET}"

echo "── smoke(redis): RedisReplication ${NAMESPACE}/${CR_NAME} exists"
kubectl -n "${NAMESPACE}" get "redisreplication/${CR_NAME}" >/dev/null

# The operator does not publish standard Ready conditions on RedisReplication;
# gate on StatefulSets and pods instead.
wait_statefulset "${CR_NAME}"
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod \
  -l "app=${CR_NAME},redis_setup_type=replication" --timeout="${TIMEOUT}" >/dev/null

PASSWORD="$(kubectl -n "${NAMESPACE}" get secret "${CREDENTIALS_SECRET}" -o jsonpath='{.data.password}' | base64 -d)"
[ -n "${PASSWORD}" ] || { echo "FAIL: redis password is empty" >&2; exit 1; }

POD="$(
  kubectl -n "${NAMESPACE}" get pod \
    -l "app=${CR_NAME},redis_setup_type=replication" \
    -o jsonpath='{.items[0].metadata.name}'
)"
[ -n "${POD}" ] || { echo "FAIL: no Redis pod found for ${CR_NAME}" >&2; exit 1; }

echo "── smoke(redis): PING via ${MASTER_SERVICE} from ${POD}"
if ! kubectl -n "${NAMESPACE}" exec "${POD}" -- \
  env REDISCLI_AUTH="${PASSWORD}" redis-cli -h "${MASTER_SERVICE}" PING 2>/dev/null | grep -q PONG; then
  echo "  (retry via localhost)"
  MASTER_SERVICE="127.0.0.1"
  kubectl -n "${NAMESPACE}" exec "${POD}" -- \
    env REDISCLI_AUTH="${PASSWORD}" redis-cli -h "127.0.0.1" -p 6379 PING | grep -q PONG
fi

KEY="smoke-redis-$(date +%s)-$$"
VAL="ok-$(date +%s)"
echo "── smoke(redis): SET/GET ${KEY}"
if ! kubectl -n "${NAMESPACE}" exec "${POD}" -- \
  env REDISCLI_AUTH="${PASSWORD}" redis-cli -h "${MASTER_SERVICE}" \
  SET "${KEY}" "${VAL}" EX 60 2>/dev/null | grep -q OK; then
  kubectl -n "${NAMESPACE}" exec "${POD}" -- \
    env REDISCLI_AUTH="${PASSWORD}" redis-cli -h "127.0.0.1" -p 6379 \
    SET "${KEY}" "${VAL}" EX 60 | grep -q OK
  GOT="$(kubectl -n "${NAMESPACE}" exec "${POD}" -- \
    env REDISCLI_AUTH="${PASSWORD}" redis-cli -h "127.0.0.1" -p 6379 GET "${KEY}")"
else
  GOT="$(kubectl -n "${NAMESPACE}" exec "${POD}" -- \
    env REDISCLI_AUTH="${PASSWORD}" redis-cli -h "${MASTER_SERVICE}" GET "${KEY}")"
fi
[ "${GOT}" = "${VAL}" ] || { echo "FAIL: GET returned '${GOT}', expected '${VAL}'" >&2; exit 1; }

echo "── smoke(redis): AOF enabled"
AOF="$(kubectl -n "${NAMESPACE}" exec "${POD}" -- \
  env REDISCLI_AUTH="${PASSWORD}" redis-cli -h "${MASTER_SERVICE}" CONFIG GET appendonly 2>/dev/null ||   kubectl -n "${NAMESPACE}" exec "${POD}" -- \
  env REDISCLI_AUTH="${PASSWORD}" redis-cli -h "127.0.0.1" -p 6379 CONFIG GET appendonly)"
echo "${AOF}" | grep -q "yes" || { echo "FAIL: AOF not enabled: ${AOF}" >&2; exit 1; }
INFO="$(kubectl -n "${NAMESPACE}" exec "${POD}" -- \
  env REDISCLI_AUTH="${PASSWORD}" redis-cli -h "${MASTER_SERVICE}" INFO persistence 2>/dev/null ||   kubectl -n "${NAMESPACE}" exec "${POD}" -- \
  env REDISCLI_AUTH="${PASSWORD}" redis-cli -h "127.0.0.1" -p 6379 INFO persistence)"
echo "${INFO}" | grep -q "aof_enabled:1" || {
  echo "FAIL: INFO persistence missing aof_enabled:1: ${INFO}" >&2
  exit 1
}

if kubectl -n "${NAMESPACE}" get statefulset "${CR_NAME}-s" >/dev/null 2>&1; then
  wait_statefulset "${CR_NAME}-s"
  SPOD="$(
    kubectl -n "${NAMESPACE}" get pod -l "app=${CR_NAME}-s" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
  )"
  [ -n "${SPOD}" ] || { echo "FAIL: no Sentinel pod found for ${CR_NAME}-s" >&2; exit 1; }

  echo "── smoke(redis): SENTINEL get-master-addr-by-name mymaster"
  MASTER_ADDR="$(kubectl -n "${NAMESPACE}" exec "${SPOD}" -- \
    redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster)"
  echo "${MASTER_ADDR}" | grep -q . || {
    echo "FAIL: Sentinel did not report master for mymaster" >&2
    exit 1
  }
  echo "  $(echo "${MASTER_ADDR}" | tr '\n' ' ')"
  kubectl -n "${NAMESPACE}" exec "${SPOD}" -- \
    redis-cli -p 26379 SENTINEL ckquorum mymaster | grep -q OK || {
    echo "FAIL: SENTINEL ckquorum mymaster not OK" >&2
    exit 1
  }
else
  echo "  (no embedded Sentinel; local/dev)"
fi

echo "[OK] smoke(redis): ${CR_NAME} Ready, PING/SET/GET ok, AOF enabled"
