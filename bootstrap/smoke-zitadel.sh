#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-zitadel.sh — verify the E2 edge for Zitadel: Vault/ESO projections
# synced, bootstrap Jobs completed, both Deployments rolled out, the sca-ca
# Certificate ready, Kong Ingresses bound to the edge hostname, and the OIDC
# discovery document served through Kong advertising the canonical issuer.
#
# Selective smoke for the zitadel component; driven by
# `make smoke COMPONENT=zitadel` (see docs/ci-cd.md). Service-side OIDC client
# flows remain in the E3 cutover.
set -euo pipefail

NAMESPACE="${ZITADEL_NS:-zitadel}"
GATEWAY_NAMESPACE="${ZITADEL_GATEWAY_NS:-kong}"
HOST="${ZITADEL_SMOKE_HOST:-zitadel.local}"
EXPECTED_ISSUER="${ZITADEL_EXPECTED_ISSUER:-https://${HOST}}"
LOCAL_PORT="${ZITADEL_SMOKE_PORT:-19443}"
TIMEOUT="${SMOKE_TIMEOUT:-600s}"
TLS_SECRET="${ZITADEL_TLS_SECRET:-zitadel-tls}"

pf_pid=""
ca_file=""
cleanup() {
  if [ -n "$pf_pid" ]; then
    kill "$pf_pid" 2>/dev/null || true
    wait "$pf_pid" 2>/dev/null || true
  fi
  if [ -n "$ca_file" ]; then
    rm -f "$ca_file"
  fi
}
trap cleanup EXIT

wait_externalsecret() {
  local name="$1" reason=""
  echo "── smoke(zitadel): ExternalSecret ${NAMESPACE}/${name} SecretSynced"
  for attempt in {1..120}; do
    reason="$(kubectl -n "$NAMESPACE" get externalsecret "$name" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || true)"
    [ "$reason" = "SecretSynced" ] && return 0
    [ "$attempt" -eq 120 ] && {
      echo "FAIL: ExternalSecret ${NAMESPACE}/${name} never reached SecretSynced (last: ${reason:-<none>})" >&2
      kubectl -n "$NAMESPACE" get externalsecret "$name" -o yaml >&2 2>/dev/null || true
      exit 1
    }
    sleep 5
  done
}

wait_job() {
  local name="$1"
  echo "── smoke(zitadel): Job ${NAMESPACE}/${name} Complete"
  kubectl -n "$NAMESPACE" wait --for=condition=complete "job/${name}" --timeout="$TIMEOUT" >/dev/null
}

echo "── smoke(zitadel): namespace ${NAMESPACE} present"
kubectl get namespace "$NAMESPACE" --no-headers >/dev/null

wait_externalsecret zitadel-masterkey
wait_externalsecret zitadel-db-credentials
wait_externalsecret zitadel-login-session

echo "── smoke(zitadel): projected Secret keys wired"
masterkey="$(kubectl -n "$NAMESPACE" get secret zitadel-masterkey -o jsonpath='{.data.masterkey}' 2>/dev/null || true)"
[ -n "$masterkey" ] || { echo "FAIL: zitadel-masterkey has no 'masterkey' key" >&2; exit 1; }
dsn="$(kubectl -n "$NAMESPACE" get secret zitadel-db-credentials -o jsonpath='{.data.dsn}' 2>/dev/null | base64 -d || true)"
case "$dsn" in
  *"dbname=zitadel"*) ;;
  *) echo "FAIL: zitadel-db-credentials dsn does not point to dbname=zitadel" >&2; exit 1 ;;
esac
session_len="$(kubectl -n "$NAMESPACE" get secret zitadel-login-session \
  -o jsonpath='{.data.ZITADEL_SESSION_COOKIE_SECRET}' 2>/dev/null | base64 -d | wc -c)"
[ "$session_len" -ge 32 ] || {
  echo "FAIL: ZITADEL_SESSION_COOKIE_SECRET is ${session_len} bytes, expected at least 32" >&2
  exit 1
}
echo "  masterkey + dsn + session cookie secret present"

echo "── smoke(zitadel): edge Certificate ${NAMESPACE}/${TLS_SECRET} Ready (sca-ca TLS)"
kubectl wait --for=condition=Ready "certificate/${TLS_SECRET}" -n "$NAMESPACE" --timeout="$TIMEOUT" >/dev/null
kubectl get secret "$TLS_SECRET" -n "$NAMESPACE" --no-headers >/dev/null
echo "  Certificate Ready, secret/${TLS_SECRET} present"

echo "── smoke(zitadel): Kong Ingresses ${NAMESPACE}/zitadel-api and zitadel-login"
for ingress in zitadel-api zitadel-login; do
  ingress_class="$(kubectl -n "$NAMESPACE" get ingress "$ingress" -o jsonpath='{.spec.ingressClassName}' 2>/dev/null || true)"
  [ "$ingress_class" = "kong" ] || {
    echo "FAIL: ingress/${ingress} class '${ingress_class:-<missing>}', expected kong" >&2
    exit 1
  }
  tls_secret="$(kubectl -n "$NAMESPACE" get ingress "$ingress" -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null || true)"
  [ "$tls_secret" = "$TLS_SECRET" ] || {
    echo "FAIL: ingress/${ingress} TLS secret '${tls_secret:-<missing>}', expected ${TLS_SECRET}" >&2
    exit 1
  }
done
api_host="$(kubectl -n "$NAMESPACE" get ingress zitadel-api -o jsonpath='{.spec.rules[0].host}')"
login_path="$(kubectl -n "$NAMESPACE" get ingress zitadel-login -o jsonpath='{.spec.rules[0].http.paths[0].path}')"
[ "$api_host" = "$HOST" ] || { echo "FAIL: ingress/zitadel-api host '${api_host}', expected ${HOST}" >&2; exit 1; }
[ "$login_path" = "/ui/v2/login" ] || { echo "FAIL: ingress/zitadel-login path '${login_path}', expected /ui/v2/login" >&2; exit 1; }
upstream_protocol="$(kubectl -n "$NAMESPACE" get service zitadel -o jsonpath='{.metadata.annotations.konghq\.com/protocol}' 2>/dev/null || true)"
[ "$upstream_protocol" = "grpc" ] || {
  echo "FAIL: service/zitadel upstream protocol '${upstream_protocol:-<missing>}', expected grpc" >&2
  exit 1
}
route_protocols="$(kubectl -n "$NAMESPACE" get ingress zitadel-api -o jsonpath='{.metadata.annotations.konghq\.com/protocols}' 2>/dev/null || true)"
[ "$route_protocols" = "https,grpcs" ] || {
  echo "FAIL: ingress/zitadel-api protocols '${route_protocols:-<missing>}', expected https,grpcs" >&2
  exit 1
}
echo "  ingress class=kong, host=${HOST}, login path=/ui/v2/login, upstream=grpc"

wait_job zitadel-init
wait_job zitadel-setup

echo "── smoke(zitadel): Deployments ${NAMESPACE}/zitadel and ${NAMESPACE}/zitadel-login Ready"
kubectl -n "$NAMESPACE" rollout status deployment/zitadel --timeout="$TIMEOUT" >/dev/null
kubectl -n "$NAMESPACE" rollout status deployment/zitadel-login --timeout="$TIMEOUT" >/dev/null
echo "  zitadel + zitadel-login Ready"

echo "── smoke(zitadel): port-forward ${GATEWAY_NAMESPACE}/kong-proxy ${LOCAL_PORT}:443"
kubectl -n "$GATEWAY_NAMESPACE" port-forward "service/kong-proxy" "${LOCAL_PORT}:443" >/dev/null 2>&1 &
pf_pid=$!
for _ in $(seq 1 60); do
  if curl -ks -o /dev/null "https://127.0.0.1:${LOCAL_PORT}/" 2>/dev/null; then break; fi
  kill -0 "$pf_pid" 2>/dev/null || { echo "FAIL: port-forward to kong-proxy died" >&2; exit 1; }
  sleep 1
done

ca_file="$(mktemp)"
verify=(-k)
if kubectl -n "$NAMESPACE" get secret "$TLS_SECRET" -o jsonpath='{.data.ca\.crt}' 2>/dev/null \
    | base64 --decode > "$ca_file" 2>/dev/null && [ -s "$ca_file" ]; then
  verify=(--cacert "$ca_file")
else
  echo "  (no ca.crt in secret/${TLS_SECRET}; verifying with -k only)" >&2
fi
curl_common=(-fsS "${verify[@]}" --resolve "${HOST}:${LOCAL_PORT}:127.0.0.1")
base_url="https://${HOST}:${LOCAL_PORT}"

echo "── smoke(zitadel): wait for Kong to serve ${HOST} with secret/${TLS_SECRET}"
discovery=""
for attempt in $(seq 1 60); do
  if discovery="$(curl "${curl_common[@]}" "${base_url}/.well-known/openid-configuration" 2>/dev/null)" \
      && curl "${curl_common[@]}" -o /dev/null "${base_url}/ui/v2/login/ready" 2>/dev/null; then
    break
  fi
  if [ "$attempt" -eq 60 ]; then
    echo "FAIL: Kong did not serve discovery + login UI for ${HOST} with secret/${TLS_SECRET} within 120s" >&2
    curl "${curl_common[@]}" -o /dev/null "${base_url}/.well-known/openid-configuration" >&2 || true
    kubectl -n "$GATEWAY_NAMESPACE" logs deployment/kong -c ingress-controller --tail=50 >&2 2>/dev/null || true
    exit 1
  fi
  sleep 2
done

echo "── smoke(zitadel): OIDC discovery issuer ${EXPECTED_ISSUER}"
issuer="$(printf '%s' "$discovery" | grep -o '"issuer":"[^"]*"' | head -n1 | cut -d'"' -f4)"
[ "$issuer" = "$EXPECTED_ISSUER" ] || {
  echo "FAIL: discovery issuer '${issuer:-<missing>}', expected '${EXPECTED_ISSUER}'" >&2
  exit 1
}
for endpoint in authorization_endpoint token_endpoint jwks_uri; do
  printf '%s' "$discovery" | grep -q "\"${endpoint}\"" || {
    echo "FAIL: discovery does not advertise ${endpoint}" >&2
    exit 1
  }
done
echo "  authorization_endpoint + token_endpoint + jwks_uri present"

printf '[OK] smoke(zitadel): Kong edge TLS Ready, discovery=%s, login UI routed\n' "$EXPECTED_ISSUER"
