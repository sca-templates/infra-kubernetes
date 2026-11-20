#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-cni.sh — single-node smoke for the bootstrap-managed CNI substrate.
# Proves the D3 dataplane is live (Calico + kube-proxy Ready, WireGuard enabled,
# node key published, Felix WireGuard metrics scrapeable) and that pod-to-pod
# HTTP works on the Floci EKS node. Multi-node WireGuard peers are covered by
# the D2 PoC harness (poc/calico-wireguard/). See docs/ci-cd.md.
set -euo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/versions.sh
. "${SELF_DIR}/versions.sh"

NAMESPACE="${CNI_SMOKE_NAMESPACE:-sca-cni-smoke}"
TIMEOUT="${CNI_SMOKE_TIMEOUT:-120s}"
EKS_CONTEXT="${FLOCI_EKS_CONTEXT:-floci-eks}"
KUBE=(kubectl)
[ -n "${EKS_CONTEXT}" ] && KUBE+=(--context "${EKS_CONTEXT}")
SERVER_IMAGE="${CNI_SMOKE_SERVER_IMAGE}"

kube() {
  "${KUBE[@]}" "$@"
}

delete_smoke_namespace() {
  kube delete namespace "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true
  for _ in $(seq 1 60); do
    kube get namespace "${NAMESPACE}" >/dev/null 2>&1 || return 0
    sleep 2
  done
  kube patch namespace "${NAMESPACE}" --type=merge -p '{"spec":{"finalizers":[]}}' >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    kube get namespace "${NAMESPACE}" >/dev/null 2>&1 || return 0
    sleep 2
  done
  echo "ERROR: namespace ${NAMESPACE} did not terminate" >&2
  return 1
}

cleanup() {
  if [ "${SMOKE_KEEP:-0}" = "1" ]; then
    echo "── cni smoke namespace kept (SMOKE_KEEP=1): ${NAMESPACE}"
  else
    delete_smoke_namespace || true
  fi
}
trap cleanup EXIT

echo "── smoke(cni): Calico substrate + WireGuard + pod networking"
delete_smoke_namespace
kube -n kube-system rollout status daemonset/calico-node --timeout="${TIMEOUT}" >/dev/null
kube -n kube-system rollout status daemonset/kube-proxy --timeout="${TIMEOUT}" >/dev/null

wireguard_enabled="$(kube get felixconfiguration default \
  -o jsonpath='{.spec.wireguardEnabled}' 2>/dev/null || true)"
[ "${wireguard_enabled}" = "true" ] || {
  echo "FAIL: default FelixConfiguration does not enable WireGuard" >&2
  exit 1
}

kube create namespace "${NAMESPACE}" --dry-run=client -o yaml | kube apply -f - >/dev/null

nodes=()
while IFS= read -r node; do
  [ -n "${node}" ] && nodes+=("${node}")
done < <(kube get nodes --no-headers -o custom-columns=NAME:.metadata.name)
[ "${#nodes[@]}" -gt 0 ] || { echo "FAIL: no nodes in context ${EKS_CONTEXT}" >&2; exit 1; }

idx=0
for node in "${nodes[@]}"; do
  idx=$(( idx + 1 ))
  pod="cni-metrics-${idx}"
  pubkey="$(kube get node "${node}" \
    -o jsonpath='{.metadata.annotations.projectcalico\.org/WireguardPublicKey}' 2>/dev/null || true)"
  [ -n "${pubkey}" ] || {
    echo "FAIL: node ${node} has no WireGuard public key annotation" >&2
    exit 1
  }

  overrides="$(printf '{"spec":{"nodeName":"%s","hostNetwork":true,"automountServiceAccountToken":false,"containers":[{"name":"curl","image":"%s","command":["sleep","3600"]}]}}' \
    "${node}" "${CNI_SMOKE_CLIENT_IMAGE}")"
  kube run "${pod}" -n "${NAMESPACE}" \
    --image="${CNI_SMOKE_CLIENT_IMAGE}" --restart=Never --overrides="${overrides}" >/dev/null
  kube wait -n "${NAMESPACE}" --for=condition=Ready "pod/${pod}" --timeout="${TIMEOUT}" >/dev/null

  felix_metrics=0
  wireguard_metrics=0
  for attempt in $(seq 1 20); do
    metrics="$(kube exec -n "${NAMESPACE}" "${pod}" -- \
      curl -fsS --max-time 5 http://127.0.0.1:9091/metrics 2>/dev/null || true)"
    if printf '%s\n' "${metrics}" | grep -q '^felix_'; then
      felix_metrics=1
    fi
    if printf '%s\n' "${metrics}" | grep '^wireguard_meta{' \
      | grep -F 'iface="wireguard.cali"' \
      | grep -Fq "public_key=\"${pubkey}\""; then
      wireguard_metrics=1
      break
    fi
    sleep 2
  done
  [ "${felix_metrics}" -eq 1 ] || {
    echo "FAIL: Felix metrics not reachable on node ${node}" >&2
    exit 1
  }
  if [ "${wireguard_metrics}" -eq 1 ]; then
    echo "[OK] node ${node}: WireGuard interface ${pubkey} exporting Felix metrics"
  elif [ "${#nodes[@]}" -eq 1 ]; then
    echo "[OK] node ${node}: WireGuard key published; single-node cluster has no peer interface metrics"
  else
    echo "FAIL: no WireGuard interface metrics for node ${node} key ${pubkey}" >&2
    kube exec -n "${NAMESPACE}" "${pod}" -- \
      curl -fsS --max-time 5 http://127.0.0.1:9091/metrics 2>&1 | grep wireguard || true
    exit 1
  fi
  kube delete -n "${NAMESPACE}" "pod/${pod}" --ignore-not-found >/dev/null || true
done

kube run cni-smoke-server -n "${NAMESPACE}" --image="${SERVER_IMAGE}" --restart=Never --port=8080 >/dev/null
kube wait -n "${NAMESPACE}" --for=condition=Ready pod/cni-smoke-server --timeout="${TIMEOUT}" >/dev/null
server_ip="$(kube get pod cni-smoke-server -n "${NAMESPACE}" -o jsonpath='{.status.podIP}')"
[ -n "${server_ip}" ] || { echo "FAIL: cni-smoke-server has no pod IP" >&2; exit 1; }

kube run cni-smoke-client -n "${NAMESPACE}" \
  --image="${CNI_SMOKE_CLIENT_IMAGE}" --restart=Never --command -- sleep 3600 >/dev/null
kube wait -n "${NAMESPACE}" --for=condition=Ready pod/cni-smoke-client --timeout="${TIMEOUT}" >/dev/null
if ! kube exec -n "${NAMESPACE}" cni-smoke-client -- \
  curl -fsS --max-time 10 "http://${server_ip}:8080/" 2>/dev/null | grep -qi nginx; then
  echo "FAIL: pod-to-pod HTTP ${server_ip}:8080 did not return the nginx page" >&2
  kube -n "${NAMESPACE}" get pods -o wide || true
  exit 1
fi

echo "[OK] smoke(cni): Calico ${CALICO_VERSION}, kube-proxy ${KUBE_PROXY_VERSION}, WireGuard on; pod networking OK"
