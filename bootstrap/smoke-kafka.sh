#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-kafka.sh — verify the Phase 11 event backbone is ready and usable:
# the SCRAM admin credentials were projected from Vault, the `Kafka` cluster
# and `KafkaUser` report Ready, and a SASL_SSL/SCRAM-SHA-512 client can create
# a topic, produce a record and consume it through the internal listener.
# Selective smoke for the kafka component; driven by
# `make smoke COMPONENT=kafka` (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${KAFKA_NAMESPACE:-data}"
CLUSTER="${KAFKA_CLUSTER:-kafka}"
POOL="${KAFKA_NODEPOOL:-kafka}"
USER_NAME="${KAFKA_USER:-scram-admin}"
CREDENTIALS_SECRET="${KAFKA_CREDENTIALS_SECRET:-kafka-scram-admin}"
TIMEOUT="${SMOKE_TIMEOUT:-600s}"
CONSUMER_TIMEOUT_MS="${KAFKA_CONSUMER_TIMEOUT_MS:-60000}"

BROKER="${KAFKA_BOOTSTRAP:-kafka-kafka-bootstrap.${NAMESPACE}.svc:9092}"
POD=""
TOPIC=""
CLIENT_CONFIG="/tmp/kafka-client.properties"
TRUSTSTORE="/tmp/kafka-ca.crt"

cleanup() {
  if [ -n "${POD}" ] && [ -n "${TOPIC}" ]; then
    kubectl -n "${NAMESPACE}" exec "${POD}" -- \
      /opt/kafka/bin/kafka-topics.sh \
      --bootstrap-server "${BROKER}" \
      --command-config "${CLIENT_CONFIG}" \
      --delete --if-exists --topic "${TOPIC}" >/dev/null 2>&1 || true
  fi
  if [ -n "${POD}" ]; then
    kubectl -n "${NAMESPACE}" exec "${POD}" -- \
      rm -f "${CLIENT_CONFIG}" "${TRUSTSTORE}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

wait_externalsecret() {
  local name="$1" reason=""
  echo "── smoke(kafka): ExternalSecret ${NAMESPACE}/${name} SecretSynced"
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

kafka_exec() {
  kubectl -n "${NAMESPACE}" exec "${POD}" -- "$@"
}

wait_externalsecret "${CREDENTIALS_SECRET}"

echo "── smoke(kafka): Kafka/${CLUSTER} Ready"
kubectl -n "${NAMESPACE}" wait --for=condition=Ready "kafka/${CLUSTER}" --timeout="${TIMEOUT}" >/dev/null

echo "── smoke(kafka): KafkaUser/${USER_NAME} Ready"
kubectl -n "${NAMESPACE}" wait --for=condition=Ready "kafkauser/${USER_NAME}" --timeout="${TIMEOUT}" >/dev/null

echo "── smoke(kafka): broker pods Ready"
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod \
  -l "strimzi.io/cluster=${CLUSTER},strimzi.io/node-pool=${POOL}" --timeout="${TIMEOUT}" >/dev/null

POD="$(
  kubectl -n "${NAMESPACE}" get pod \
    -l "strimzi.io/cluster=${CLUSTER},strimzi.io/node-pool=${POOL}" \
    -o jsonpath='{.items[0].metadata.name}'
)"
[ -n "${POD}" ] || { echo "FAIL: no broker pod for ${CLUSTER}/${POOL}" >&2; exit 1; }

USERNAME="$(kubectl -n "${NAMESPACE}" get secret "${CREDENTIALS_SECRET}" -o jsonpath='{.data.username}' | base64 -d)"
PASSWORD="$(kubectl -n "${NAMESPACE}" get secret "${CREDENTIALS_SECRET}" -o jsonpath='{.data.password}' | base64 -d)"
[ -n "${USERNAME}" ] && [ -n "${PASSWORD}" ] || {
  echo "FAIL: projected Kafka credentials are empty" >&2
  exit 1
}

echo "── smoke(kafka): install SASL_SSL client config in ${POD}"
kubectl -n "${NAMESPACE}" get secret "${CLUSTER}-cluster-ca-cert" \
  -o jsonpath='{.data.ca\.crt}' \
  | base64 -d \
  | kubectl -n "${NAMESPACE}" exec -i "${POD}" -- sh -c 'umask 077; cat > /tmp/kafka-ca.crt'

kubectl -n "${NAMESPACE}" exec -i "${POD}" -- sh -c 'umask 077; cat > /tmp/kafka-client.properties' <<EOF
security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="${USERNAME}" password="${PASSWORD}";
ssl.truststore.type=PEM
ssl.truststore.location=${TRUSTSTORE}
EOF

REPLICAS="$(kubectl -n "${NAMESPACE}" get kafkanodepool "${POOL}" -o jsonpath='{.spec.replicas}')"
REPLICAS="${REPLICAS:-1}"
if [ "${REPLICAS}" -gt 3 ]; then
  REPLICATION_FACTOR=3
else
  REPLICATION_FACTOR="${REPLICAS}"
fi

TOPIC="smoke-kafka-$(date +%s)"
GROUP="smoke-kafka-$(date +%s)"
MESSAGE="smoke-$(date +%s)-$$"

echo "── smoke(kafka): create topic ${TOPIC} (RF=${REPLICATION_FACTOR})"
kafka_exec /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server "${BROKER}" \
  --command-config "${CLIENT_CONFIG}" \
  --create --if-not-exists --topic "${TOPIC}" \
  --partitions 1 --replication-factor "${REPLICATION_FACTOR}"

echo "── smoke(kafka): produce and consume through SASL_SSL/SCRAM"
printf '%s\n' "${MESSAGE}" | kubectl -n "${NAMESPACE}" exec -i "${POD}" -- \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server "${BROKER}" \
  --command-config "${CLIENT_CONFIG}" \
  --topic "${TOPIC}"

received="$(
  kafka_exec /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server "${BROKER}" \
    --command-config "${CLIENT_CONFIG}" \
    --topic "${TOPIC}" \
    --group "${GROUP}" \
    --from-beginning --max-messages 1 \
    --timeout-ms "${CONSUMER_TIMEOUT_MS}"
)"
[ "${received}" = "${MESSAGE}" ] || {
  echo "FAIL: consumed '${received}', expected '${MESSAGE}'" >&2
  exit 1
}

echo "  ${POD} → ${TOPIC}: ${received}"

echo "[OK] smoke(kafka): ${CLUSTER} Ready, ${USER_NAME} authenticated, produce/consume through TLS+SCRAM"
