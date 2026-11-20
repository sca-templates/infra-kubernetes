#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# cni-emulator.sh — bootstrap-managed CNI substrate for the Floci emulated EKS
# cluster (dev/CI tooling only, docs/ci-cd.md). Floci is started with its bundled
# CNI/kube-proxy disabled; this script installs the D2-validated Calico iptables
# + VXLAN + WireGuard dataplane and a pinned kube-proxy DaemonSet before ArgoCD
# touches the platform. No catalog row, no Application, no sync-wave.
set -euo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SELF_DIR}/.." && pwd)"

for _sca_env in "${REPO_ROOT}/.env" ".env"; do
  if [ -f "$_sca_env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$_sca_env"
    break
  fi
done
unset _sca_env

# shellcheck source=bootstrap/versions.sh
. "${SELF_DIR}/versions.sh"

ACTION="${1:-}"
CNI_ENV="${CNI_ENV:-local}"
CNI_PROFILE_PATH="${CNI_PROFILE_PATH:-${REPO_ROOT}/envs/${CNI_ENV}/cni.yaml}"
CNI_GENERATED_DIR="${CNI_GENERATED_DIR:-${REPO_ROOT}/.generated/cni}"
EKS_CONTEXT="${FLOCI_EKS_CONTEXT:-floci-eks}"
KUBE=(kubectl)
[ -n "${EKS_CONTEXT}" ] && KUBE+=(--context "${EKS_CONTEXT}")
CNI_TIMEOUT="${CNI_TIMEOUT:-10m}"

kube() {
  "${KUBE[@]}" "$@"
}

profile_value() {
  awk -v key="$1" '
    $1 == key ":" {
      sub(/^[^:]*:[ \t]*/, "", $0)
      gsub(/^["]|["]$/, "", $0)
      print
      exit
    }
  ' "${CNI_PROFILE_PATH}"
}

check_profile() {
  local provider version dataplane wireguard mtu pod_cidr kube_proxy_image kernel
  [ -f "${CNI_PROFILE_PATH}" ] || {
    echo "ERROR: CNI profile not found: ${CNI_PROFILE_PATH}" >&2
    return 1
  }
  provider="$(profile_value provider)"
  version="$(profile_value version)"
  dataplane="$(profile_value dataplane)"
  wireguard="$(profile_value wireguardEnabled)"
  mtu="$(profile_value mtu)"
  pod_cidr="$(profile_value podCIDR)"
  kube_proxy_image="$(profile_value kubeProxyImage)"
  [ "${provider}" = "calico" ] || {
    echo "ERROR: unsupported CNI provider '${provider}' in ${CNI_PROFILE_PATH}" >&2
    return 1
  }
  [ "${version}" = "${CALICO_VERSION}" ] || {
    echo "ERROR: CNI profile version ${version} != pinned ${CALICO_VERSION}" >&2
    return 1
  }
  [ "${dataplane}" = "iptables" ] || {
    echo "ERROR: unsupported dataplane '${dataplane}'; D3 gates iptables only" >&2
    return 1
  }
  [ "${wireguard}" = "true" ] || {
    echo "ERROR: WireGuard must be enabled in the D3 substrate profile" >&2
    return 1
  }
  [ "${kube_proxy_image}" = "${KUBE_PROXY_IMAGE}" ] || {
    echo "ERROR: kube-proxy image ${kube_proxy_image} != pinned ${KUBE_PROXY_IMAGE}" >&2
    return 1
  }
  case "${mtu}" in
    ''|*[!0-9]*) echo "ERROR: invalid CNI MTU '${mtu}'" >&2; return 1 ;;
  esac
  case "${pod_cidr}" in
    */*) ;;
    *) echo "ERROR: invalid pod CIDR '${pod_cidr}'" >&2; return 1 ;;
  esac
  [ "${#CALICO_MANIFEST_SHA256}" -eq 64 ] || {
    echo "ERROR: CALICO_MANIFEST_SHA256 is not a sha256 digest" >&2
    return 1
  }
  kernel="$(uname -r)"
  if ! awk -v k="${kernel}" 'BEGIN {split(k, a, "."); exit !(a[1] > 5 || (a[1] == 5 && a[2] >= 10))}'; then
    echo "ERROR: kernel ${kernel} is below the Calico WireGuard minimum (5.10)" >&2
    return 1
  fi
}

check_cluster() {
  if ! kube get nodes --request-timeout=10s >/dev/null 2>&1; then
    echo "ERROR: context '${EKS_CONTEXT}' is not reachable" >&2
    return 1
  fi
  if ! kube get nodes --no-headers 2>/dev/null | grep -q .; then
    echo "ERROR: no node object in context '${EKS_CONTEXT}'" >&2
    kube get nodes -o wide 2>/dev/null || true
    return 1
  fi
}

preflight() {
  echo "── cni: preflight (${CNI_ENV}, provider calico/${CALICO_VERSION}, dataplane iptables)"
  check_profile
  check_cluster
  local floating_tag
  floating_tag="lat""est"
  if ! grep -RIn --include='*.yaml' ":${floating_tag}" "${REPO_ROOT}/bootstrap/cni" >/dev/null; then
    echo "  no floating tags in bootstrap/cni"
  else
    echo "ERROR: floating ${floating_tag} tag in bootstrap/cni" >&2
    return 1
  fi
  echo "[OK] cni preflight"
}

render() {
  local source output pod_cidr kube_proxy_image
  pod_cidr="$(profile_value podCIDR)"
  kube_proxy_image="$(profile_value kubeProxyImage)"

  mkdir -p "${CNI_GENERATED_DIR}"
  CNI_MTU="$(profile_value mtu)" \
  CNI_POD_CIDR="${pod_cidr}" \
  CNI_IP_DETECTION_METHOD="$(profile_value ipDetectionMethod)" \
    "${SELF_DIR}/cni/render-calico.sh" "${CNI_GENERATED_DIR}/calico.yaml"

  for source in "${SELF_DIR}"/cni/manifests/*.yaml; do
    [ -f "${source}" ] || continue
    output="${CNI_GENERATED_DIR}/$(basename "${source}")"
    sed -e "s#10\.42\.0\.0/16#${pod_cidr}#g" \
        -e "s#registry\.k8s\.io/kube-proxy:v[^[:space:]]*#${kube_proxy_image}#g" \
        "${source}" > "${output}"
    echo "  rendered ${output} (${kube_proxy_image}, ${pod_cidr})"
  done
}

wait_for_felix_config() {
  local attempt
  for attempt in $(seq 1 60); do
    if kube get felixconfiguration default >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "ERROR: default FelixConfiguration was not created" >&2
  return 1
}

check_kubernetes_service() {
  local pod="cni-kubernetes-probe"
  local attempt phase overrides probe node

  node="$(kube get nodes --no-headers -o custom-columns=NAME:.metadata.name | awk 'NR == 1 { print; exit }')"
  [ -n "${node}" ] || {
    echo "ERROR: no node available for the internal API probe" >&2
    return 1
  }

  kube -n kube-system delete pod "${pod}" --ignore-not-found >/dev/null 2>&1 || true

  probe='curl -fsS --max-time 10 --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc.cluster.local/version'
  overrides="$(printf '{"spec":{"nodeName":"%s","hostNetwork":true,"automountServiceAccountToken":true,"containers":[{"name":"curl","image":"%s","command":["sh","-c","%s"]}]}}' \
    "${node}" "${CNI_SMOKE_CLIENT_IMAGE}" "${probe//\"/\\\"}")"

  if ! kube -n kube-system run "${pod}" \
    --image="${CNI_SMOKE_CLIENT_IMAGE}" --restart=Never --overrides="${overrides}" >/dev/null; then
    echo "ERROR: cannot create the internal API probe pod" >&2
    return 1
  fi

  phase=""
  for attempt in $(seq 1 90); do
    phase="$(kube -n kube-system get pod "${pod}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    [ "${phase}" = "Succeeded" ] && break
    [ "${phase}" = "Failed" ] && break
    sleep 2
  done

  if [ "${phase}" != "Succeeded" ]; then
    kube -n kube-system describe pod "${pod}" >&2 || true
    kube -n kube-system logs "${pod}" >&2 || true
    echo "ERROR: Kubernetes ClusterIP is not reachable from inside the cluster" >&2
    kube -n kube-system delete pod "${pod}" --ignore-not-found >/dev/null 2>&1 || true
    return 1
  fi

  kube -n kube-system delete pod "${pod}" --ignore-not-found >/dev/null 2>&1 || true
}

cni_up() {
  preflight
  render

  echo "── cni: applying pinned kube-proxy DaemonSet"
  for manifest in "${CNI_GENERATED_DIR}"/kube-proxy*.yaml; do
    [ -f "${manifest}" ] || continue
    kube apply -f "${manifest}" >/dev/null
  done
  if ! kube -n kube-system rollout status daemonset/kube-proxy --timeout="${CNI_TIMEOUT}"; then
    kube -n kube-system get pods -l k8s-app=kube-proxy -o wide || true
    echo "ERROR: kube-proxy rollout did not complete" >&2
    return 1
  fi

  echo "── cni: probing internal Kubernetes Service"
  check_kubernetes_service

  local api_ip api_port
  api_ip="$(kube -n default get endpoints kubernetes -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)"
  api_port="$(kube -n default get endpoints kubernetes -o jsonpath='{.subsets[0].ports[0].port}' 2>/dev/null)"
  if [ -z "${api_ip}" ] || [ -z "${api_port}" ]; then
    echo "ERROR: cannot resolve the kubernetes API endpoint" >&2
    return 1
  fi
  kube -n kube-system create configmap kubernetes-services-endpoint \
    --from-literal="KUBERNETES_SERVICE_HOST=${api_ip}" \
    --from-literal="KUBERNETES_SERVICE_PORT=${api_port}" \
    --dry-run=client -o yaml | kube apply -f - >/dev/null

  echo "── cni: applying Calico substrate"
  if ! kube apply -f "${CNI_GENERATED_DIR}/calico.yaml" >/dev/null; then
    kube -n kube-system get pods -o wide || true
    echo "ERROR: Calico substrate did not apply" >&2
    return 1
  fi
  kube wait --for=condition=Established crd/felixconfigurations.crd.projectcalico.org --timeout="${CNI_TIMEOUT}" >/dev/null
  kube apply -f "${CNI_GENERATED_DIR}/felix-config-default.yaml" >/dev/null
  wait_for_felix_config

  echo "── cni: enabling WireGuard + WireGuard metrics before rollout"
  kube patch felixconfiguration default --type=merge \
    -p '{"spec":{"wireguardEnabled":true,"prometheusMetricsEnabled":true,"prometheusWireGuardMetricsEnabled":true}}' >/dev/null
  kube -n kube-system rollout restart daemonset/calico-node >/dev/null

  if ! kube -n kube-system rollout status daemonset/calico-node --timeout="${CNI_TIMEOUT}"; then
    kube -n kube-system get pods -l k8s-app=calico-node -o wide || true
    echo "ERROR: calico-node rollout did not complete" >&2
    return 1
  fi

  echo "[OK] cni substrate ready (calico ${CALICO_VERSION}, kube-proxy ${KUBE_PROXY_VERSION}, WireGuard on)"
}

cni_down() {
  echo "── cni: removing bootstrap-managed resources"
  for manifest in "${CNI_GENERATED_DIR}"/kube-proxy*.yaml "${CNI_GENERATED_DIR}"/felix-config-default.yaml; do
    [ -f "${manifest}" ] || continue
    kube delete -f "${manifest}" --ignore-not-found >/dev/null 2>&1 || true
  done
  if [ -f "${CNI_GENERATED_DIR}/calico.yaml" ]; then
    kube delete -f "${CNI_GENERATED_DIR}/calico.yaml" --ignore-not-found >/dev/null 2>&1 || true
  fi
  kube -n kube-system delete configmap kubernetes-services-endpoint --ignore-not-found >/dev/null 2>&1 || true
  echo "[OK] cni resources removed; full rollback requires reverting the D3 commit and make eks-down"
}

cni_status() {
  echo "── cni: substrate status"
  kube -n kube-system get daemonset calico-node kube-proxy -o wide 2>/dev/null || true
  kube get felixconfiguration default -o jsonpath='{.spec.wireguardEnabled}{"\n"}' 2>/dev/null || true
  kube get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.projectcalico\.org/WireguardPublicKey}{"\n"}{end}' 2>/dev/null || true
}

case "${ACTION}" in
  up) cni_up ;;
  down) cni_down ;;
  status) cni_status ;;
  preflight) preflight ;;
  render) render ;;
  *)
    echo "usage: $0 up|down|status|preflight|render" >&2
    exit 2
    ;;
esac
