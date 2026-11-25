#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${PLUGIN_BARMAN_CLOUD_NS:-cloudnative-pg}"
DEPLOYMENT="${PLUGIN_BARMAN_CLOUD_DEPLOYMENT:-plugin-barman-cloud}"
CONFIG_MAP="${PLUGIN_BARMAN_CLOUD_CONFIG_MAP:-plugin-barman-cloud-config}"
SERVICE="${PLUGIN_BARMAN_CLOUD_SERVICE:-barman-cloud}"
CRD="${PLUGIN_BARMAN_CLOUD_CRD:-objectstores.barmancloud.cnpg.io}"
OPERATOR_IMAGE="${PLUGIN_BARMAN_CLOUD_IMAGE:-ghcr.io/cloudnative-pg/plugin-barman-cloud:v0.16.0}"
SIDECAR_IMAGE="${PLUGIN_BARMAN_CLOUD_SIDECAR_IMAGE:-ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.16.0}"
TIMEOUT="${SMOKE_TIMEOUT:-120s}"

echo "── smoke(plugin-barman-cloud): namespace ${NAMESPACE} present"
kubectl get namespace "$NAMESPACE" --no-headers >/dev/null

echo "── smoke(plugin-barman-cloud): deployment ${NAMESPACE}/${DEPLOYMENT} Ready"
kubectl -n "$NAMESPACE" rollout status "deployment/${DEPLOYMENT}" --timeout="$TIMEOUT" >/dev/null

actual_image="$(kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="barman-cloud")].image}')"
[ "$actual_image" = "$OPERATOR_IMAGE" ] || {
  echo "FAIL: plugin image '${actual_image}', expected '${OPERATOR_IMAGE}'" >&2
  exit 1
}
echo "  image → ${actual_image}"

actual_sidecar="$(kubectl -n "$NAMESPACE" get configmap "$CONFIG_MAP" \
  -o jsonpath='{.data.SIDECAR_IMAGE}')"
[ "$actual_sidecar" = "$SIDECAR_IMAGE" ] || {
  echo "FAIL: sidecar image '${actual_sidecar}', expected '${SIDECAR_IMAGE}'" >&2
  exit 1
}
echo "  sidecar image → ${actual_sidecar}"

echo "── smoke(plugin-barman-cloud): service ${NAMESPACE}/${SERVICE} present"
kubectl -n "$NAMESPACE" get service "$SERVICE" --no-headers >/dev/null

echo "── smoke(plugin-barman-cloud): ${CRD} Established"
kubectl get crd "$CRD" --no-headers >/dev/null
kubectl wait --for=condition=Established "crd/${CRD}" --timeout="$TIMEOUT" >/dev/null

echo "[OK] smoke(plugin-barman-cloud): plugin Ready, image pins verified, ObjectStore CRD Established"
