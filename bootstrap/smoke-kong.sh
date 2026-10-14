#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-kong.sh — verify Kong is deployed DB-less with the bundled Kubernetes
# Ingress Controller, that its CRDs are Established, the `kong` IngressClass
# exists, the cert-manager-issued proxy Certificate is Ready, and — the project
# gate — that the committed declarative route is actually served: a TLS request
# to the proxy for `https://kong.local/demo` returns the request-termination
# response (HTTP 200). Selective smoke for the kong component; driven by
# `make smoke COMPONENT=kong` (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${KONG_NS:-kong}"
TIMEOUT="${SMOKE_TIMEOUT:-120s}"
ROLLOUT_TIMEOUT="${KONG_ROLLOUT_TIMEOUT:-300}"
LOCAL_PORT="${KONG_SMOKE_PORT:-18000}"
HOST="${KONG_SMOKE_HOST:-kong.local}"
ROUTE_PATH="${KONG_SMOKE_PATH:-/demo}"
EXPECT_BODY="${KONG_SMOKE_BODY:-kong ok}"
CERT="${KONG_PROXY_CERT:-kong-proxy}"
SECRET="${KONG_PROXY_SECRET:-kong-proxy-cert}"
INGRESS_CLASS="${KONG_INGRESS_CLASS:-kong}"

# The `configuration.konghq.com` CRDs the bundled Kubernetes Ingress Controller
# programs Kong from (a representative subset of the 12 the chart ships).
# KongPlugin is the one the committed demo route uses (demo-termination-plugin).
EXPECTED_CRDS=(
  kongplugins.configuration.konghq.com
  kongclusterplugins.configuration.konghq.com
  kongingresses.configuration.konghq.com
  tcpingresses.configuration.konghq.com
  kongupstreampolicies.configuration.konghq.com
)

pf_pid=""
ca_file=""
cleanup() {
  if [ -n "$pf_pid" ]; then
    kill "$pf_pid" 2>/dev/null || true
    wait "$pf_pid" 2>/dev/null || true
  fi
  [ -n "$ca_file" ] && rm -f "$ca_file" 2>/dev/null || true
}
trap cleanup EXIT

echo "── smoke(kong): namespace ${NAMESPACE} present"
kubectl get namespace "$NAMESPACE" --no-headers >/dev/null

echo "── smoke(kong): gateway Deployment ${NAMESPACE}/kong Ready (proxy + ingress-controller)"
kubectl -n "$NAMESPACE" rollout status "deployment/kong" --timeout="${ROLLOUT_TIMEOUT}s" >/dev/null

# DB-less is the whole point: no database, no drift, routing declared in git.
echo "── smoke(kong): DB-less (KONG_DATABASE=off)"
db="$(kubectl -n "$NAMESPACE" get deployment kong \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="proxy")].env[?(@.name=="KONG_DATABASE")].value}')"
if [ "$db" != "off" ]; then
  echo "FAIL: KONG_DATABASE='${db:-<unset>}', expected 'off' (DB-less)" >&2
  exit 1
fi
echo "  KONG_DATABASE=off (DB-less)"

echo "── smoke(kong): IngressClass ${INGRESS_CLASS}"
kubectl get ingressclass "$INGRESS_CLASS" --no-headers >/dev/null

echo "── smoke(kong): ${EXPECTED_CRDS[*]}"
missing=0
for crd in "${EXPECTED_CRDS[@]}"; do
  if ! kubectl get crd "$crd" --no-headers >/dev/null 2>&1; then
    echo "FAIL: CRD ${crd} is missing" >&2
    missing=1
    continue
  fi
  kubectl wait --for=condition=Established "crd/${crd}" --timeout="$TIMEOUT" >/dev/null
  echo "  ${crd} → Established"
done
[ "$missing" -eq 0 ] || { echo "FAIL: one or more kong CRDs are missing (above)" >&2; exit 1; }

echo "── smoke(kong): the committed declarative config is applied (Ingress + KongPlugin)"
kubectl -n "$NAMESPACE" get ingress kong-demo --no-headers >/dev/null
kubectl -n "$NAMESPACE" get kongplugin demo-termination --no-headers >/dev/null
echo "  ingress/kong-demo + kongplugin/demo-termination present"

echo "── smoke(kong): proxy Certificate ${NAMESPACE}/${CERT} Ready (sca-ca TLS)"
kubectl wait --for=condition=Ready "certificate/${CERT}" -n "$NAMESPACE" --timeout="$TIMEOUT" >/dev/null
kubectl get secret "$SECRET" -n "$NAMESPACE" --no-headers >/dev/null
echo "  Certificate Ready, secret/${SECRET} present"

echo "── smoke(kong): serving the route over TLS → GET https://${HOST}${ROUTE_PATH}"
kubectl -n "$NAMESPACE" port-forward "service/kong-proxy" "${LOCAL_PORT}:443" >/dev/null 2>&1 &
pf_pid=$!
# Wait until the forwarded port accepts a TLS connection (any status).
for _ in $(seq 1 30); do
  if curl -ks -o /dev/null "https://127.0.0.1:${LOCAL_PORT}/" 2>/dev/null; then break; fi
  kill -0 "$pf_pid" 2>/dev/null || { echo "FAIL: port-forward to kong-proxy died" >&2; exit 1; }
  sleep 1
done

# Verify the chain against the cert-manager CA (secret ca.crt, sca-ca root) so a
# served certificate is proven, not merely accepted with -k. Fall back to -k only
# if the secret carries no CA bundle.
ca_file="$(mktemp)"
verify=(-k)
if kubectl -n "$NAMESPACE" get secret "$SECRET" -o jsonpath='{.data.ca\.crt}' 2>/dev/null \
    | base64 --decode > "$ca_file" 2>/dev/null && [ -s "$ca_file" ]; then
  verify=(--cacert "$ca_file")
else
  echo "  (no ca.crt in secret/${SECRET}; verifying with -k only)" >&2
fi

curl_common=(-s "${verify[@]}" --resolve "${HOST}:${LOCAL_PORT}:127.0.0.1")
code="$(curl "${curl_common[@]}" -o /dev/null -w '%{http_code}' \
  "https://${HOST}:${LOCAL_PORT}${ROUTE_PATH}" 2>/dev/null || true)"
body="$(curl "${curl_common[@]}" "https://${HOST}:${LOCAL_PORT}${ROUTE_PATH}" 2>/dev/null || true)"

if [ "$code" != "200" ]; then
  echo "FAIL: GET ${ROUTE_PATH} returned HTTP ${code:-<none>} (expected 200)" >&2
  echo "  body: ${body}" >&2
  kubectl -n "$NAMESPACE" get ingress,kongplugin -o wide >&2 2>/dev/null || true
  kubectl -n "$NAMESPACE" logs deployment/kong -c ingress-controller --tail=50 >&2 2>/dev/null || true
  exit 1
fi

case "$body" in
  *"${EXPECT_BODY}"*) ;;
  *) echo "FAIL: body '${body}' does not contain '${EXPECT_BODY}'" >&2; exit 1 ;;
esac
echo "  HTTP 200, body: ${body}"

echo "[OK] smoke(kong): gateway Ready, DB-less, IngressClass ${INGRESS_CLASS}, ${#EXPECTED_CRDS[@]} CRDs Established, TLS Certificate Ready, route ${ROUTE_PATH} → 200"
