#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-zitadel.sh — verify the E1 internal-only Zitadel deployment: Vault/ESO
# projections synced, the chart init/setup Jobs completed, both Deployments
# rolled out, no Ingress exists yet, and the h2c discovery document served through
# a local port-forward advertises the issuer derived from the chart ConfigMap.
#
# Selective smoke for the zitadel component; driven by
# `make smoke COMPONENT=zitadel` (see docs/ci-cd.md). Edge/OIDC client flows are
# deferred to E2.
set -euo pipefail

NAMESPACE="${ZITADEL_NS:-zitadel}"
LOCAL_PORT="${ZITADEL_SMOKE_PORT:-18080}"
TIMEOUT="${SMOKE_TIMEOUT:-600s}"

pf_pid=""
cleanup() {
  if [ -n "$pf_pid" ]; then
    kill "$pf_pid" 2>/dev/null || true
    wait "$pf_pid" 2>/dev/null || true
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

yaml_value() {
  local key="$1" config="$2"
  printf '%s\n' "$config" | awk -v key="${key}:" '$1 == key { $1 = ""; sub(/^ /, ""); print; exit }'
}

curl_h2c() {
  if ! curl --version 2>/dev/null | grep -q ' HTTP2 '; then
    echo "FAIL: curl has no HTTP/2 support; the Zitadel h2c smoke requires it" >&2
    return 1
  fi
  curl --http2-prior-knowledge "$@"
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

echo "── smoke(zitadel): no Ingress in ${NAMESPACE} (E1 internal-only)"
ingresses="$(kubectl -n "$NAMESPACE" get ingress --no-headers 2>/dev/null || true)"
[ -z "$ingresses" ] || {
  echo "FAIL: E1 must not expose an Ingress; found: ${ingresses}" >&2
  exit 1
}

wait_job zitadel-init
wait_job zitadel-setup

echo "── smoke(zitadel): Deployments ${NAMESPACE}/zitadel and ${NAMESPACE}/zitadel-login Ready"
kubectl -n "$NAMESPACE" rollout status deployment/zitadel --timeout="$TIMEOUT" >/dev/null
kubectl -n "$NAMESPACE" rollout status deployment/zitadel-login --timeout="$TIMEOUT" >/dev/null
kubectl -n "$NAMESPACE" wait --for=condition=Ready pod \
  -l "app.kubernetes.io/instance=zitadel,app.kubernetes.io/component=start" --timeout="$TIMEOUT" >/dev/null
kubectl -n "$NAMESPACE" wait --for=condition=Ready pod \
  -l "app.kubernetes.io/instance=zitadel,app.kubernetes.io/component=login" --timeout="$TIMEOUT" >/dev/null

config="$(kubectl -n "$NAMESPACE" get configmap zitadel-config-yaml -o jsonpath='{.data.zitadel-config-yaml}')"
domain="$(yaml_value ExternalDomain "$config")"
port="$(yaml_value ExternalPort "$config")"
secure="$(yaml_value ExternalSecure "$config")"
[ -n "$domain" ] || { echo "FAIL: zitadel-config-yaml has no ExternalDomain" >&2; exit 1; }
if [ "$secure" = "true" ]; then
  scheme="https"
else
  scheme="http"
fi
expected_issuer="${scheme}://${domain}"
case "$port" in
  "" | 80)
    [ "$scheme" = "http" ] && expected_issuer="${expected_issuer}:80"
    ;;
  443)
    [ "$scheme" = "http" ] && expected_issuer="${expected_issuer}:443"
    ;;
  *)
    expected_issuer="${expected_issuer}:${port}"
    ;;
esac

echo "── smoke(zitadel): port-forward service/zitadel ${LOCAL_PORT}:8080"
kubectl -n "$NAMESPACE" port-forward "service/zitadel" "${LOCAL_PORT}:8080" >/dev/null 2>&1 &
pf_pid=$!
for _ in $(seq 1 60); do
  if curl_h2c -s -o /dev/null "http://127.0.0.1:${LOCAL_PORT}/debug/ready" 2>/dev/null; then break; fi
  kill -0 "$pf_pid" 2>/dev/null || { echo "FAIL: port-forward to service/zitadel died" >&2; exit 1; }
  sleep 1
done

echo "── smoke(zitadel): OIDC discovery issuer ${expected_issuer}"
discovery=""
for attempt in $(seq 1 60); do
  if discovery="$(curl_h2c -sS -H "Host: ${domain}" \
    "http://127.0.0.1:${LOCAL_PORT}/.well-known/openid-configuration" 2>/dev/null)"; then
    break
  fi
  if [ "$attempt" -eq 60 ]; then
    echo "FAIL: Zitadel did not serve OIDC discovery within 120s" >&2
    kubectl -n "$NAMESPACE" logs deployment/zitadel --tail=50 >&2 2>/dev/null || true
    exit 1
  fi
  sleep 2
done

issuer="$(printf '%s' "$discovery" | grep -o '"issuer"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)"
[ "$issuer" = "$expected_issuer" ] || {
  echo "FAIL: discovery issuer '${issuer:-<missing>}', expected '${expected_issuer}'" >&2
  exit 1
}
for endpoint in authorization_endpoint token_endpoint jwks_uri; do
  printf '%s' "$discovery" | grep -q "\"${endpoint}\"" || {
    echo "FAIL: discovery document has no '${endpoint}'" >&2
    exit 1
  }
done

echo "[OK] smoke(zitadel): Jobs complete, h2c service Ready, discovery=${expected_issuer}, no edge (E1)"
