#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_tools docker kubectl curl perl openssl

if docker container inspect "${CALICO_WG_SERVER_NAME}" >/dev/null 2>&1 || docker container inspect "${CALICO_WG_AGENT_NAME}" >/dev/null 2>&1; then
  echo "ERROR: PoC containers already exist; run poc/calico-wireguard/down.sh first"
  exit 1
fi

mkdir -p "${CALICO_WG_GENERATED_DIR}"
if [ ! -s "${CALICO_WG_TOKEN_PATH}" ]; then
  openssl rand -hex 32 > "${CALICO_WG_TOKEN_PATH}"
  chmod 600 "${CALICO_WG_TOKEN_PATH}"
fi
K3S_TOKEN="$(<"${CALICO_WG_TOKEN_PATH}")"

docker network inspect "${CALICO_WG_NETWORK}" >/dev/null 2>&1 || docker network create --driver bridge --subnet "${CALICO_WG_SUBNET}" "${CALICO_WG_NETWORK}" >/dev/null

docker run --detach \
  --name "${CALICO_WG_SERVER_NAME}" \
  --hostname "${CALICO_WG_SERVER_NAME}" \
  --network "${CALICO_WG_NETWORK}" \
  --ip "${CALICO_WG_SERVER_IP}" \
  --privileged \
  --publish "${CALICO_WG_API_PORT}:6443" \
  --env "K3S_TOKEN=${K3S_TOKEN}" \
  --env K3S_KUBECONFIG_OUTPUT=/output/server-kubeconfig.yaml \
  --env K3S_KUBECONFIG_MODE=0644 \
  --volume "${CALICO_WG_GENERATED_DIR}:/output" \
  "${CALICO_WG_K3S_IMAGE}" server \
  --cluster-cidr 10.244.0.0/16 \
  --service-cidr 10.96.0.0/12 \
  --flannel-backend none \
  --disable-network-policy \
  --disable traefik \
  --disable servicelb \
  --node-label calico-wg.sca.local/role=server \
  --kubelet-arg=fail-cgroupv1=false \
  --tls-san 127.0.0.1 \
  --tls-san localhost

for attempt in $(seq 1 60); do
  if [ -s "${CALICO_WG_SERVER_KUBECONFIG}" ]; then
    break
  fi
  sleep 2
done

if [ ! -s "${CALICO_WG_SERVER_KUBECONFIG}" ]; then
  echo "ERROR: k3s did not write ${CALICO_WG_SERVER_KUBECONFIG}"
  docker logs "${CALICO_WG_SERVER_NAME}" || true
  exit 1
fi

cp "${CALICO_WG_SERVER_KUBECONFIG}" "${CALICO_WG_KUBECONFIG_PATH}"
sed -i "s|https://127.0.0.1:6443|https://127.0.0.1:${CALICO_WG_API_PORT}|g" "${CALICO_WG_KUBECONFIG_PATH}"
context="$(kubectl --kubeconfig "${CALICO_WG_KUBECONFIG_PATH}" config current-context)"
kubectl --kubeconfig "${CALICO_WG_KUBECONFIG_PATH}" config rename-context "${context}" calico-wg-poc >/dev/null

docker run --detach \
  --name "${CALICO_WG_AGENT_NAME}" \
  --hostname "${CALICO_WG_AGENT_NAME}" \
  --network "${CALICO_WG_NETWORK}" \
  --ip "${CALICO_WG_AGENT_IP}" \
  --privileged \
  --env "K3S_URL=https://${CALICO_WG_SERVER_IP}:6443" \
  --env "K3S_TOKEN=${K3S_TOKEN}" \
  "${CALICO_WG_K3S_IMAGE}" agent \
  --node-label calico-wg.sca.local/role=agent \
  --kubelet-arg=fail-cgroupv1=false

for attempt in $(seq 1 60); do
  if kube get --raw=/readyz >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! kube get --raw=/readyz >/dev/null 2>&1; then
  echo "ERROR: k3s API did not become ready"
  docker logs "${CALICO_WG_SERVER_NAME}" || true
  exit 1
fi

curl -fsSL "${CALICO_WG_MANIFEST_URL}" -o "${CALICO_WG_MANIFEST_PATH}"
perl -0pi -e 's/  veth_mtu: "0"/  veth_mtu: "1440"/; s/            # - name: CALICO_IPV4POOL_CIDR/            - name: CALICO_IPV4POOL_CIDR/; s/            #   value: "192.168.0.0\/16"/              value: "10.244.0.0\/16"/; s/(name: CALICO_IPV4POOL_VXLAN\n              value: )"CrossSubnet"/${1}"Always"/; s/(            - name: IP\n              value: "autodetect"\n)/$1            - name: IP_AUTODETECTION_METHOD\n              value: "interface=eth0"\n/; s/          "mtu": __CNI_MTU__,/          "mtu": __CNI_MTU__,\n          "container_settings": {"allow_ip_forwarding": true},/' "${CALICO_WG_MANIFEST_PATH}"

perl -0pi -e '
  s/        # This init container mounts the necessary filesystems needed by the BPF data plane.*?          securityContext:\n            privileged: true\n//s;
  s/            # For eBPF mode, we need to be able to mount the BPF filesystem at \/sys\/fs\/bpf so we mount in the\n            # parent directory\.\n            - name: bpffs\n              mountPath: \/sys\/fs\/bpf\n//;
  s/        - name: sys-fs\n          hostPath:\n            path: \/sys\/fs\/\n            type: DirectoryOrCreate\n//;
  s/        - name: bpffs\n          hostPath:\n            path: \/sys\/fs\/bpf\n            type: Directory\n//;
  s/        # mount \/proc at \/nodeproc to be used by ebpf-bootstrap initContainer to mount root cgroup2 fs\.\n        - name: nodeproc\n          hostPath:\n            path: \/proc\n//;
' "${CALICO_WG_MANIFEST_PATH}"

perl -0pi -e '
  s/            - name: sys-kernel-security\n              mountPath: \/sys\/kernel\/security\n//;
  s/        # securityfs, read by Felix to detect kernel lockdown=confidentiality\.\n        # No type set \(like nodeproc below\) so nodes without securityfs still\n        # start; Felix treats an unreadable lockdown file as "not locked down"\.\n        - name: sys-kernel-security\n          hostPath:\n            path: \/sys\/kernel\/security\n//;
' "${CALICO_WG_MANIFEST_PATH}"

if grep -Eq 'name: "ebpf-bootstrap"|mountPropagation: Bidirectional|name: sys-fs|name: bpffs|name: nodeproc|sys-kernel-security' "${CALICO_WG_MANIFEST_PATH}"; then
  echo "ERROR: Calico substrate manifest patch did not apply"
  exit 1
fi

grep -q 'value: "10.244.0.0/16"' "${CALICO_WG_MANIFEST_PATH}" || { echo "ERROR: Calico pod CIDR patch did not apply"; exit 1; }
grep -q 'value: "Always"' "${CALICO_WG_MANIFEST_PATH}" || { echo "ERROR: Calico VXLAN patch did not apply"; exit 1; }
grep -q 'allow_ip_forwarding' "${CALICO_WG_MANIFEST_PATH}" || { echo "ERROR: Calico CNI forwarding patch did not apply"; exit 1; }

if ! kube apply -f "${CALICO_WG_MANIFEST_PATH}" >/dev/null; then
  kube -n kube-system get pods -o wide || true
  echo "ERROR: Calico installation did not apply"
  exit 1
fi

kube wait --for=condition=Established crd/felixconfigurations.crd.projectcalico.org --timeout=5m >/dev/null

felix_config_ready=false
for attempt in $(seq 1 60); do
  if kube get felixconfiguration default >/dev/null 2>&1; then
    felix_config_ready=true
    break
  fi
  sleep 2
done
if [ "${felix_config_ready}" != true ]; then
  echo "ERROR: default FelixConfiguration was not created"
  exit 1
fi

kube patch felixconfiguration default --type=merge -p '{"spec":{"wireguardEnabled":true,"prometheusMetricsEnabled":true,"prometheusWireGuardMetricsEnabled":true}}' >/dev/null
kube -n kube-system rollout restart daemonset/calico-node >/dev/null

if ! kube -n kube-system rollout status daemonset/calico-node --timeout=10m; then
  kube -n kube-system get pods -l k8s-app=calico-node -o wide || true
  for pod in $(kube -n kube-system get pods -l k8s-app=calico-node -o name 2>/dev/null || true); do
    kube -n kube-system describe "${pod}" || true
    kube -n kube-system logs "${pod}" --all-containers --tail=200 || true
  done
  echo "ERROR: Calico nodes did not become ready"
  exit 1
fi

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

echo "CALICO_WG_POC_UP_OK"
echo "Kubeconfig: ${CALICO_WG_KUBECONFIG_PATH}"
kube get nodes -o wide
