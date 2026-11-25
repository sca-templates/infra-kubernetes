#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_tools kubectl jq

kube apply -f "${COMMON_DIR}/smoke-namespace.yaml" >/dev/null
kube apply -f "${COMMON_DIR}/smoke-server.yaml" >/dev/null
kube apply -f "${COMMON_DIR}/smoke-service.yaml" >/dev/null
kube apply -f "${COMMON_DIR}/smoke-client.yaml" >/dev/null
kube -n calico-wg-poc rollout status deployment/nginx-server --timeout=5m >/dev/null
kube -n calico-wg-poc rollout status deployment/curl-client --timeout=5m >/dev/null

metrics_pod_for_node() {
  printf 'calico-wg-metrics-%s' "$1"
}

metrics_for_node() {
  local pod
  pod="$(metrics_pod_for_node "$1")"
  kube -n kube-system exec "${pod}" -c curl -- curl -fsS --max-time 5 http://127.0.0.1:9091/metrics
}

wireguard_metrics_for_node() {
  local node="$1" metrics
  for attempt in $(seq 1 15); do
    metrics="$(metrics_for_node "${node}" 2>/dev/null || true)"
    if printf '%s\n' "${metrics}" | grep -q '^wireguard_meta{'; then
      printf '%s\n' "${metrics}"
      return 0
    fi
    sleep 1
  done
  return 1
}

numeric_value() {
  awk -v v="${1:-0}" 'BEGIN { if (v ~ /^[0-9.]+([eE][-+]?[0-9]+)?$/) printf "%.0f", v; else print 0 }'
}

server_key="$(kube get node "${CALICO_WG_SERVER_NAME}" -o jsonpath='{.metadata.annotations.projectcalico\.org/WireguardPublicKey}')"
agent_key="$(kube get node "${CALICO_WG_AGENT_NAME}" -o jsonpath='{.metadata.annotations.projectcalico\.org/WireguardPublicKey}')"
if [ -z "${server_key}" ] || [ -z "${agent_key}" ]; then
  echo "ERROR: WireGuard public keys are missing from node annotations"
  exit 1
fi

server_node="$(kube -n calico-wg-poc get pod -l app=nginx-server -o jsonpath='{.items[0].spec.nodeName}')"
client_node="$(kube -n calico-wg-poc get pod -l app=curl-client -o jsonpath='{.items[0].spec.nodeName}')"
server_pod_ip="$(kube -n calico-wg-poc get pod -l app=nginx-server -o jsonpath='{.items[0].status.podIP}')"
if [ -z "${server_node}" ] || [ -z "${client_node}" ] || [ "${server_node}" = "${client_node}" ]; then
  echo "ERROR: smoke pods are not on different nodes (server=${server_node:-none}, client=${client_node:-none})"
  exit 1
fi
if [ -z "${server_pod_ip}" ]; then
  echo "ERROR: server pod has no IP"
  exit 1
fi

response="$(kube -n calico-wg-poc exec deployment/curl-client -c curl -- sh -c "curl -fsS --max-time 10 http://${server_pod_ip}:8080/")"
echo "${response}" | grep -q 'Welcome to nginx!' || { echo "ERROR: cross-node HTTP response was unexpected"; exit 1; }

mkdir -p "${CALICO_WG_GENERATED_DIR}"
now="$(date +%s)"
metrics_pods=("$(metrics_pod_for_node "${CALICO_WG_SERVER_NAME}")" "$(metrics_pod_for_node "${CALICO_WG_AGENT_NAME}")")
cleanup_metrics_pods() {
  kube -n kube-system delete pod "${metrics_pods[@]}" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup_metrics_pods EXIT

for node in "${CALICO_WG_SERVER_NAME}" "${CALICO_WG_AGENT_NAME}"; do
  pod="$(metrics_pod_for_node "${node}")"
  kube -n kube-system run "${pod}" \
    --image="${CALICO_WG_CLIENT_IMAGE}" \
    --restart=Never \
    --overrides="$(jq -nc --arg node "${node}" --arg image "${CALICO_WG_CLIENT_IMAGE}" '{spec:{nodeName:$node,hostNetwork:true,automountServiceAccountToken:false,containers:[{name:"curl",image:$image,command:["sleep","3600"]}]}}')" >/dev/null
done
kube -n kube-system wait --for=condition=Ready "${metrics_pods[@]/#/pod/}" --timeout=2m >/dev/null

metrics_ready=false
if wireguard_metrics_for_node "${CALICO_WG_SERVER_NAME}" >/dev/null && wireguard_metrics_for_node "${CALICO_WG_AGENT_NAME}" >/dev/null; then
  metrics_ready=true
fi
if [ "${metrics_ready}" != true ]; then
  echo "ERROR: Felix WireGuard metrics were not registered; wireguardEnabled must be set before calico-node starts"
  echo "FelixConfiguration default:"
  kube get felixconfiguration default -o yaml || true
  echo "Calico node WireGuard log lines:"
  for pod in $(kube -n kube-system get pods -l k8s-app=calico-node -o name 2>/dev/null || true); do
    echo "--- ${pod}"
    kube -n kube-system logs "${pod}" -c calico-node --tail=500 2>/dev/null | grep -i wireguard || true
  done
  exit 1
fi

for entry in "${CALICO_WG_SERVER_NAME}:${server_key}:${agent_key}" "${CALICO_WG_AGENT_NAME}:${agent_key}:${server_key}"; do
  IFS=: read -r node local_key expected_peer_key <<<"${entry}"
  metrics="$(wireguard_metrics_for_node "${node}")" || { echo "ERROR: Felix WireGuard metrics disappeared on ${node}"; exit 1; }
  {
    echo "node=${node}"
    echo "local-public-key=${local_key}"
    echo "expected-peer-key=${expected_peer_key}"
    printf '%s\n' "${metrics}" | grep -E '^wireguard_(meta|latest_handshake_seconds|bytes_sent|bytes_rcvd)\{' || true
  } | tee "${CALICO_WG_GENERATED_DIR}/${node}-wireguard.txt"

  meta="$(printf '%s\n' "${metrics}" | grep '^wireguard_meta{' | grep -F "iface=\"wireguard.cali\"" | grep -F "public_key=\"${local_key}\"" | tail -n1 || true)"
  [ -n "${meta}" ] || { echo "ERROR: WireGuard interface metadata is missing on ${node}"; exit 1; }
  peer_handshakes="$(printf '%s\n' "${metrics}" | grep '^wireguard_latest_handshake_seconds{' | grep -F "peer_key=\"${expected_peer_key}\"" || true)"
  [ -n "${peer_handshakes}" ] || { echo "ERROR: expected WireGuard peer is missing on ${node}"; exit 1; }
  peer_count="$(printf '%s\n' "${peer_handshakes}" | grep -c . || true)"
  [ "${peer_count}" -eq 1 ] || { echo "ERROR: expected one WireGuard peer on ${node}, got ${peer_count}"; exit 1; }
  handshake="$(numeric_value "${peer_handshakes##* }")"
  [ "${handshake}" -gt 0 ] && [ $((now - handshake)) -lt 600 ] || { echo "ERROR: no recent WireGuard handshake on ${node}"; exit 1; }
  for metric in bytes_sent bytes_rcvd; do
    line="$(printf '%s\n' "${metrics}" | grep "^wireguard_${metric}{" | grep -F "peer_key=\"${expected_peer_key}\"" | tail -n1 || true)"
    value="$(numeric_value "${line##* }")"
    [ "${value}" -gt 0 ] || { echo "ERROR: WireGuard ${metric} is zero on ${node}"; exit 1; }
  done
done

echo "CALICO_WG_SMOKE_OK"
echo "Cross-node HTTP: ${client_node} -> ${server_node}"
echo "Encryption scope: host-to-host only; pod-to-host and same-node pod traffic remain plaintext"
