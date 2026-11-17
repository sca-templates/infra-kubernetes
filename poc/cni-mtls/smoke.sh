#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_tools kubectl jq

if [ ! -s "${CNI_MTLS_KUBECONFIG_PATH}" ]; then
  echo "ERROR: missing ${CNI_MTLS_KUBECONFIG_PATH}; run poc/cni-mtls/up.sh first"
  exit 1
fi

kube apply -f "${COMMON_DIR}/smoke-namespace.yaml"
kube apply -f "${COMMON_DIR}/smoke-server.yaml"
kube apply -f "${COMMON_DIR}/smoke-service.yaml"
kube apply -f "${COMMON_DIR}/smoke-client.yaml"

for deployment in nginx-server curl-client; do
  ready_replicas=""
  for attempt in $(seq 1 60); do
    ready_replicas="$(kube -n cni-mtls-poc get deployment "${deployment}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    if [ "${ready_replicas}" = "1" ]; then
      break
    fi
    sleep 2
  done
  if [ "${ready_replicas}" != "1" ]; then
    echo "ERROR: deployment ${deployment} did not become ready"
    kube -n cni-mtls-poc get pods -o wide || true
    exit 1
  fi
done

server_node="$(kube -n cni-mtls-poc get pod -l app=nginx-server -o jsonpath='{.items[0].spec.nodeName}')"
client_node="$(kube -n cni-mtls-poc get pod -l app=curl-client -o jsonpath='{.items[0].spec.nodeName}')"
server_pod_ip="$(kube -n cni-mtls-poc get pod -l app=nginx-server -o jsonpath='{.items[0].status.podIP}')"
if [ -z "${server_node}" ] || [ -z "${client_node}" ] || [ "${server_node}" = "${client_node}" ]; then
  echo "ERROR: smoke pods are not on different nodes (server=${server_node:-none}, client=${client_node:-none})"
  exit 1
fi
if [ -z "${server_pod_ip}" ]; then
  echo "ERROR: server pod has no IP"
  exit 1
fi

dump_cross_node_diagnostics() {
  kube -n cni-mtls-poc get pods -o wide || true
  docker exec "${CNI_MTLS_SERVER_NAME}" sh -c 'ip route' || true
  docker exec "${CNI_MTLS_AGENT_NAME}" sh -c 'ip route' || true
  for node in "${CNI_MTLS_SERVER_NAME}" "${CNI_MTLS_AGENT_NAME}"; do
    cilium_pod="$(kube -n kube-system get pods -l k8s-app=cilium --field-selector "spec.nodeName=${node}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    [ -n "${cilium_pod}" ] || continue
    kube -n kube-system exec "${cilium_pod}" -c cilium-agent -- cilium-dbg status || true
    kube -n kube-system exec "${cilium_pod}" -c cilium-agent -- cilium-dbg debuginfo --output json 2>/dev/null | jq '{wireguard: .wireguard, routes: .routes}' || true
  done
}

response="$(kube -n cni-mtls-poc exec deployment/curl-client -c curl -- sh -c "curl -fsS --max-time 10 http://${server_pod_ip}:8080/")" || {
  echo "ERROR: cross-node HTTP request failed"
  dump_cross_node_diagnostics
  exit 1
}
echo "${response}" | grep -q 'Welcome to nginx!' || { echo "ERROR: cross-node HTTP response was unexpected"; exit 1; }

for node in "${CNI_MTLS_SERVER_NAME}" "${CNI_MTLS_AGENT_NAME}"; do
  pod="$(kube -n kube-system get pods -l k8s-app=cilium --field-selector "spec.nodeName=${node}" -o jsonpath='{.items[0].metadata.name}')"
  if [ -z "${pod}" ]; then
    echo "ERROR: no Cilium pod found on ${node}"
    exit 1
  fi
  status="$(kube -n kube-system exec "${pod}" -c cilium-agent -- cilium-dbg status)"
  echo "${status}" | grep -q 'Encryption: Wireguard' || { echo "ERROR: WireGuard is not enabled on ${node}"; exit 1; }
  echo "${status}" | grep -q 'Port: 51871' || { echo "ERROR: WireGuard port is not 51871 on ${node}"; exit 1; }
  echo "${status}" | grep -q 'Peers: 1' || { echo "ERROR: expected one WireGuard peer on ${node}"; exit 1; }
  echo "${status}" | grep 'Encryption: Wireguard'
  debuginfo="$(kube -n kube-system exec "${pod}" -c cilium-agent -- cilium-dbg debuginfo --output json)"
  printf '%s' "${debuginfo}" | jq -e '.wireguard.interfaces[] | select(.name == "cilium_wg0") | .peers[] | select(.last-handshake-time != null and .last-handshake-time != "")' >/dev/null || { echo "ERROR: no recent WireGuard handshake on ${node}"; exit 1; }
done

echo "CNI_MTLS_SMOKE_OK"
echo "Cross-node HTTP: ${client_node} -> ${server_node}"
