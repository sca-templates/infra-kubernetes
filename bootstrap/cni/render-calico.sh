#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# render-calico.sh — render the pinned Calico VXLAN manifest with the D3
# substrate patches. Generated output is ephemeral CI state, not a catalog asset.
set -euo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bootstrap/versions.sh
. "${SOURCE_DIR}/versions.sh"

for tool in curl sha256sum perl; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "ERROR: required tool not found: ${tool}" >&2
    exit 1
  fi
done

OUTPUT="${1:?usage: render-calico.sh <output-path>}"
CNI_MTU="${CNI_MTU:-1440}"
CNI_POD_CIDR="${CNI_POD_CIDR:-10.42.0.0/16}"
CNI_IP_DETECTION_METHOD="${CNI_IP_DETECTION_METHOD:-interface=eth0}"
mkdir -p "$(dirname "${OUTPUT}")"
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

curl -fsSL "${CALICO_MANIFEST_URL}" -o "${tmp}"
printf '%s  %s\n' "${CALICO_MANIFEST_SHA256}" "${tmp}" | sha256sum -c - >/dev/null
cp "${tmp}" "${OUTPUT}"

CNI_MTU="${CNI_MTU:-1440}" \
CNI_POD_CIDR="${CNI_POD_CIDR:-10.42.0.0/16}" \
CNI_IP_DETECTION_METHOD="${CNI_IP_DETECTION_METHOD:-interface=eth0}" \
perl -0pi -e '
  my $mtu = $ENV{CNI_MTU};
  my $cidr = $ENV{CNI_POD_CIDR};
  my $iface = $ENV{CNI_IP_DETECTION_METHOD};
  s/  veth_mtu: "0"/  veth_mtu: "$mtu"/;
  s/            # - name: CALICO_IPV4POOL_CIDR/            - name: CALICO_IPV4POOL_CIDR/;
  s/            #   value: "192\.168\.0\.0\/16"/              value: "$cidr"/;
  s/(name: CALICO_IPV4POOL_VXLAN\n              value: )"CrossSubnet"/${1}"Always"/;
  s/(            - name: IP\n              value: "autodetect"\n)/$1            - name: IP_AUTODETECTION_METHOD\n              value: "$iface"\n/;
  s/          "mtu": __CNI_MTU__,/          "mtu": __CNI_MTU__,\n          "container_settings": {"allow_ip_forwarding": true},/;
  s/        # This init container mounts the necessary filesystems needed by the BPF data plane.*?          securityContext:\n            privileged: true\n//s;
  s/            # For eBPF mode, we need to be able to mount the BPF filesystem at \/sys\/fs\/bpf so we mount in the\n            # parent directory\.\n            - name: bpffs\n              mountPath: \/sys\/fs\/bpf\n//;
  s/        - name: sys-fs\n          hostPath:\n            path: \/sys\/fs\/\n            type: DirectoryOrCreate\n//;
  s/        - name: bpffs\n          hostPath:\n            path: \/sys\/fs\/bpf\n            type: Directory\n//;
  s/        # mount \/proc at \/nodeproc to be used by ebpf-bootstrap initContainer to mount root cgroup2 fs\.\n        - name: nodeproc\n          hostPath:\n            path: \/proc\n//;
  s/            - name: sys-kernel-security\n              mountPath: \/sys\/kernel\/security\n//;
  s/        # securityfs, read by Felix to detect kernel lockdown=confidentiality\.\n        # No type set \(like nodeproc below\) so nodes without securityfs still\n        # start; Felix treats an unreadable lockdown file as "not locked down"\.\n        - name: sys-kernel-security\n          hostPath:\n            path: \/sys\/kernel\/security\n//;
' "${OUTPUT}"

if grep -Eq 'name: "ebpf-bootstrap"|mountPropagation: Bidirectional|name: sys-fs|name: bpffs|name: nodeproc|sys-kernel-security' "${OUTPUT}"; then
  echo "ERROR: Calico substrate manifest patch did not apply" >&2
  exit 1
fi
if ! grep -Eq "veth_mtu: \"${CNI_MTU}\"" "${OUTPUT}" \
  || ! grep -Fq "value: \"${CNI_POD_CIDR}\"" "${OUTPUT}" \
  || ! grep -A1 -Fq 'name: CALICO_IPV4POOL_VXLAN' "${OUTPUT}" \
  || ! grep -Fq 'value: "Always"' "${OUTPUT}" \
  || ! grep -A1 -Fq 'name: CALICO_IPV4POOL_IPIP' "${OUTPUT}" \
  || ! grep -Fq 'value: "Never"' "${OUTPUT}"; then
  echo "ERROR: Calico profile values did not render into ${OUTPUT}" >&2
  exit 1
fi

echo "rendered ${OUTPUT} from ${CALICO_VERSION} (${CALICO_MANIFEST_SHA256})"
