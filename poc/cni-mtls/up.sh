#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_tools docker kubectl helm openssl

if docker container inspect "${CNI_MTLS_SERVER_NAME}" >/dev/null 2>&1 || docker container inspect "${CNI_MTLS_AGENT_NAME}" >/dev/null 2>&1; then
  echo "ERROR: PoC containers already exist; run poc/cni-mtls/down.sh first"
  exit 1
fi

mkdir -p "${CNI_MTLS_GENERATED_DIR}"
if [ ! -s "${CNI_MTLS_TOKEN_PATH}" ]; then
  openssl rand -hex 32 > "${CNI_MTLS_TOKEN_PATH}"
  chmod 600 "${CNI_MTLS_TOKEN_PATH}"
fi
K3S_TOKEN="$(<"${CNI_MTLS_TOKEN_PATH}")"

docker network inspect "${CNI_MTLS_NETWORK}" >/dev/null 2>&1 || docker network create --driver bridge --subnet "${CNI_MTLS_SUBNET}" "${CNI_MTLS_NETWORK}" >/dev/null

docker run --detach \
  --name "${CNI_MTLS_SERVER_NAME}" \
  --hostname "${CNI_MTLS_SERVER_NAME}" \
  --network "${CNI_MTLS_NETWORK}" \
  --ip "${CNI_MTLS_SERVER_IP}" \
  --privileged \
  --publish "${CNI_MTLS_API_PORT}:6443" \
  --env "K3S_TOKEN=${K3S_TOKEN}" \
  --env K3S_KUBECONFIG_OUTPUT=/output/server-kubeconfig.yaml \
  --env K3S_KUBECONFIG_MODE=0644 \
  --volume "${CNI_MTLS_GENERATED_DIR}:/output" \
  "${CNI_MTLS_K3S_IMAGE}" server \
  --cluster-cidr 10.244.0.0/16 \
  --service-cidr 10.96.0.0/12 \
  --flannel-backend none \
  --disable-network-policy \
  --disable traefik \
  --disable servicelb \
  --node-label cni-mtls.sca.local/role=server \
  --kubelet-arg=fail-cgroupv1=false \
  --tls-san 127.0.0.1 \
  --tls-san localhost

for attempt in $(seq 1 60); do
  if [ -s "${CNI_MTLS_SERVER_KUBECONFIG}" ]; then
    break
  fi
  sleep 2
done

if [ ! -s "${CNI_MTLS_SERVER_KUBECONFIG}" ]; then
  echo "ERROR: k3s did not write ${CNI_MTLS_SERVER_KUBECONFIG}"
  docker logs "${CNI_MTLS_SERVER_NAME}" || true
  exit 1
fi

cp "${CNI_MTLS_SERVER_KUBECONFIG}" "${CNI_MTLS_KUBECONFIG_PATH}"
sed -i "s|https://127.0.0.1:6443|https://127.0.0.1:${CNI_MTLS_API_PORT}|g" "${CNI_MTLS_KUBECONFIG_PATH}"
context="$(kubectl --kubeconfig "${CNI_MTLS_KUBECONFIG_PATH}" config current-context)"
kubectl --kubeconfig "${CNI_MTLS_KUBECONFIG_PATH}" config rename-context "${context}" cni-mtls-poc >/dev/null

docker run --detach \
  --name "${CNI_MTLS_AGENT_NAME}" \
  --hostname "${CNI_MTLS_AGENT_NAME}" \
  --network "${CNI_MTLS_NETWORK}" \
  --ip "${CNI_MTLS_AGENT_IP}" \
  --privileged \
  --env "K3S_URL=https://${CNI_MTLS_SERVER_IP}:6443" \
  --env "K3S_TOKEN=${K3S_TOKEN}" \
  "${CNI_MTLS_K3S_IMAGE}" agent \
  --node-label cni-mtls.sca.local/role=agent \
  --kubelet-arg=fail-cgroupv1=false

for attempt in $(seq 1 60); do
  if kube get --raw=/readyz >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! kube get --raw=/readyz >/dev/null 2>&1; then
  echo "ERROR: k3s API did not become ready"
  docker logs "${CNI_MTLS_SERVER_NAME}" || true
  exit 1
fi

export KUBECONFIG="${CNI_MTLS_KUBECONFIG_PATH}"
helm upgrade --install cilium cilium/cilium \
  --repo https://helm.cilium.io \
  --version "${CNI_MTLS_CILIUM_CHART_VERSION}" \
  --namespace kube-system \
  --values "${COMMON_DIR}/cilium-values.yaml" \
  --set "image.tag=${CNI_MTLS_CILIUM_IMAGE_TAG}" \
  --set "operator.image.tag=${CNI_MTLS_CILIUM_IMAGE_TAG}" \
  --wait \
  --timeout 5m

ready_count=0
for attempt in $(seq 1 90); do
  ready_count="$(kube get nodes -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | grep -c '^True$' || true)"
  if [ "${ready_count}" -eq 2 ]; then
    break
  fi
  sleep 2
done

if [ "${ready_count}" -ne 2 ]; then
  echo "ERROR: expected 2 Ready nodes, got ${ready_count}"
  kube get nodes -o wide || true
  exit 1
fi

echo "CNI_MTLS_POC_UP_OK"
echo "Kubeconfig: ${CNI_MTLS_KUBECONFIG_PATH}"
kube get nodes -o wide
