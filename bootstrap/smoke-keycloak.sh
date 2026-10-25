#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-keycloak.sh — verify the OIDC identity provider end to end: the Vault
# projections synced, the chart StatefulSet rolled out, the realm is imported,
# the edge serves the sca-ca certificate, discovery advertises the configured
# issuer, the authorization endpoint redirects an unauthenticated PKCE S256
# prompt=none request with login_required, and the smoke user can obtain a token
# that userinfo accepts.
#
# Selective smoke for the keycloak component; driven by
# `make smoke COMPONENT=keycloak` (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${KEYCLOAK_NS:-keycloak}"
GATEWAY_NAMESPACE="${KONG_NAMESPACE:-kong}"
HOST="${KEYCLOAK_SMOKE_HOST:-keycloak.local}"
LOCAL_PORT="${KEYCLOAK_SMOKE_PORT:-18443}"
REALM="${KEYCLOAK_REALM:-sca}"
CLIENT_ID="${KEYCLOAK_SMOKE_CLIENT:-sca-smoke}"
TIMEOUT="${SMOKE_TIMEOUT:-600s}"
ROLLOUT_TIMEOUT="${KEYCLOAK_ROLLOUT_TIMEOUT:-600}"
TLS_SECRET="${KEYCLOAK_TLS_SECRET:-keycloak-tls}"

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

wait_externalsecret() {
  local name="$1" reason=""
  echo "── smoke(keycloak): ExternalSecret ${NAMESPACE}/${name} SecretSynced"
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

echo "── smoke(keycloak): namespace ${NAMESPACE} present"
kubectl get namespace "$NAMESPACE" --no-headers >/dev/null

wait_externalsecret keycloak-admin
wait_externalsecret keycloak-db-credentials
wait_externalsecret keycloak-test-user

echo "── smoke(keycloak): keycloak-db-credentials is a basic-auth Secret"
db_type="$(kubectl -n "$NAMESPACE" get secret keycloak-db-credentials -o jsonpath='{.type}')"
[ "$db_type" = "kubernetes.io/basic-auth" ] || {
  echo "FAIL: secret/keycloak-db-credentials type '${db_type}', expected kubernetes.io/basic-auth" >&2
  exit 1
}
echo "  secret/keycloak-db-credentials → ${db_type}"

echo "── smoke(keycloak): StatefulSet ${NAMESPACE}/keycloak Ready"
kubectl -n "$NAMESPACE" rollout status statefulset/keycloak --timeout="${ROLLOUT_TIMEOUT}s" >/dev/null
kubectl -n "$NAMESPACE" wait --for=condition=Ready pod \
  -l "app.kubernetes.io/instance=keycloak" --timeout="$TIMEOUT" >/dev/null

echo "── smoke(keycloak): realm import + admin/test Secrets wired"
kubectl -n "$NAMESPACE" get configmap keycloak-realm-sca --no-headers >/dev/null
for key in username password; do
  value="$(kubectl -n "$NAMESPACE" get secret keycloak-admin -o "jsonpath={.data.${key}}" 2>/dev/null || true)"
  [ -n "$value" ] || { echo "FAIL: keycloak-admin has no '${key}' key" >&2; exit 1; }
done
for key in username password; do
  value="$(kubectl -n "$NAMESPACE" get secret keycloak-test-user -o "jsonpath={.data.${key}}" 2>/dev/null || true)"
  [ -n "$value" ] || { echo "FAIL: keycloak-test-user has no '${key}' key" >&2; exit 1; }
done
echo "  configmap/keycloak-realm-sca + admin/test credentials present"

echo "── smoke(keycloak): edge Certificate ${NAMESPACE}/${TLS_SECRET} Ready (sca-ca TLS)"
kubectl wait --for=condition=Ready "certificate/${TLS_SECRET}" -n "$NAMESPACE" --timeout="$TIMEOUT" >/dev/null
kubectl get secret "$TLS_SECRET" -n "$NAMESPACE" --no-headers >/dev/null
echo "  Certificate Ready, secret/${TLS_SECRET} present"

echo "── smoke(keycloak): Ingress ${NAMESPACE}/keycloak → Kong"
ingress_class="$(kubectl -n "$NAMESPACE" get ingress keycloak -o jsonpath='{.spec.ingressClassName}')"
[ "$ingress_class" = "kong" ] || {
  echo "FAIL: ingress/keycloak class '${ingress_class}', expected kong" >&2
  exit 1
}
echo "  ingress/keycloak class=kong"

expected_issuer="$(kubectl -n "$NAMESPACE" get statefulset keycloak \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="keycloak")].env[?(@.name=="KC_HOSTNAME")].value}' 2>/dev/null || true)"
expected_issuer="${KEYCLOAK_EXPECTED_ISSUER:-${expected_issuer:-https://${HOST}}}"
expected_issuer="${expected_issuer%/}/realms/${REALM}"

echo "── smoke(keycloak): port-forward ${GATEWAY_NAMESPACE}/kong-proxy ${LOCAL_PORT}:443"
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
curl_common=(-sS "${verify[@]}" --resolve "${HOST}:${LOCAL_PORT}:127.0.0.1")
base_url="https://${HOST}:${LOCAL_PORT}"

# Certificate/keycloak-tls can be Ready before Kong's Ingress Controller has
# loaded the Secret into the proxy. Wait for the served chain to verify against
# the projected CA before asserting the discovery document.
echo "── smoke(keycloak): wait for Kong to serve secret/${TLS_SECRET} for ${HOST}"
discovery=""
for attempt in $(seq 1 60); do
  if discovery="$(curl "${curl_common[@]}" "${base_url}/realms/${REALM}/.well-known/openid-configuration" 2>/dev/null)"; then
    break
  fi
  if [ "$attempt" -eq 60 ]; then
    echo "FAIL: Kong did not serve a certificate trusted by secret/${TLS_SECRET} for ${HOST} within 120s" >&2
    curl "${curl_common[@]}" -o /dev/null "${base_url}/realms/${REALM}/.well-known/openid-configuration" >&2 || true
    kubectl -n "$GATEWAY_NAMESPACE" logs deployment/kong -c ingress-controller --tail=50 >&2 2>/dev/null || true
    exit 1
  fi
  sleep 2
done

echo "── smoke(keycloak): OIDC discovery issuer ${expected_issuer}"
issuer="$(printf '%s' "$discovery" | grep -o '"issuer":"[^"]*"' | head -n1 | cut -d'"' -f4)"
[ "$issuer" = "$expected_issuer" ] || {
  echo "FAIL: discovery issuer '${issuer:-<missing>}', expected '${expected_issuer}'" >&2
  exit 1
}
printf '%s' "$discovery" | grep -q '/protocol/openid-connect/auth' || {
  echo "FAIL: discovery does not advertise the authorization endpoint" >&2
  exit 1
}
printf '%s' "$discovery" | grep -q '/protocol/openid-connect/token' || {
  echo "FAIL: discovery does not advertise the token endpoint" >&2
  exit 1
}
echo "  issuer=${issuer}"

# The sca-smoke client enforces PKCE S256, like a real public client: send a
# valid verifier/challenge pair even though prompt=none never reaches the login
# form (the expected outcome is still login_required).
code_verifier="$(openssl rand -base64 48 | tr -d '\n' | tr '+/' '-_' | tr -d '=')"
code_challenge="$(printf '%s' "$code_verifier" \
  | openssl dgst -sha256 -binary \
  | openssl base64 -A \
  | tr '+/' '-_' | tr -d '=')"

echo "── smoke(keycloak): authorization endpoint rejects an unauthenticated PKCE S256 prompt=none request"
headers="$(curl "${curl_common[@]}" -D - -o /dev/null -G \
  "${base_url}/realms/${REALM}/protocol/openid-connect/auth" \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "response_type=code" \
  --data-urlencode "scope=openid profile" \
  --data-urlencode "redirect_uri=https://${HOST}/" \
  --data-urlencode "code_challenge=${code_challenge}" \
  --data-urlencode "code_challenge_method=S256" \
  --data-urlencode "prompt=none")"
auth_code="$(printf '%s' "$headers" | awk 'NR==1{print $2}')"
location="$(printf '%s' "$headers" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p')"
[ "$auth_code" = "302" ] || {
  echo "FAIL: authorization endpoint returned HTTP ${auth_code:-<none>}, expected 302" >&2
  exit 1
}
case "$location" in
  *error=login_required*) ;;
  *) echo "FAIL: authorization redirect '${location}' does not carry error=login_required" >&2; exit 1 ;;
esac
echo "  HTTP 302 → error=login_required"

# The smoke credential is generated by bootstrap/seed-vault.sh; on an older
# local cluster, run it once to create secret/keycloak/test-user/local.
username="$(kubectl -n "$NAMESPACE" get secret keycloak-test-user -o jsonpath='{.data.username}' | base64 -d)"
password="$(kubectl -n "$NAMESPACE" get secret keycloak-test-user -o jsonpath='{.data.password}' | base64 -d)"
[ -n "$username" ] && [ -n "$password" ] || { echo "FAIL: keycloak-test-user credentials are empty" >&2; exit 1; }

echo "── smoke(keycloak): password grant + userinfo for ${username}"
token_response="$(curl "${curl_common[@]}" -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "grant_type=password" \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "username=${username}" \
  --data-urlencode "password=${password}" \
  --data-urlencode "scope=openid profile" \
  "${base_url}/realms/${REALM}/protocol/openid-connect/token" 2>/dev/null || true)"
access_token="$(printf '%s' "$token_response" | grep -o '"access_token":"[^"]*"' | head -n1 | cut -d'"' -f4)"
if [ -z "$access_token" ]; then
  echo "FAIL: token endpoint did not return an access_token" >&2
  printf '%s\n' "$token_response" | sed -E 's/"access_token":"[^"]*"/"access_token":"<redacted>"/g' >&2
  exit 1
fi
userinfo="$(curl "${curl_common[@]}" -H "Authorization: Bearer ${access_token}" \
  "${base_url}/realms/${REALM}/protocol/openid-connect/userinfo")"
preferred="$(printf '%s' "$userinfo" | grep -o '"preferred_username":"[^"]*"' | head -n1 | cut -d'"' -f4)"
[ "$preferred" = "$username" ] || {
  echo "FAIL: userinfo preferred_username '${preferred:-<missing>}', expected '${username}'" >&2
  exit 1
}
echo "  token issued, userinfo preferred_username=${preferred}"

echo "[OK] smoke(keycloak): StatefulSet Ready, realm sca imported, TLS Ready, discovery=${expected_issuer}, login_required enforced, smoke token works"
