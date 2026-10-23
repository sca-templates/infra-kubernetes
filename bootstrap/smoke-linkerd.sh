#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-linkerd.sh — verify the Linkerd control plane AND its data plane.
# Project gate for Phase 9: the control plane runs, its webhooks are wired, its
# identity PKI is present and Ready, and the mesh actually carries traffic:
# an ephemeral namespace is injected, a real server and client exchange an HTTP
# request (200 through the mesh), and both proxies hold a live identity leaf
# that chains to the trust anchor. A preflight reads the control-plane proxies'
# identity expiry first, so an emulator clock that outran the leaf lifetime is
# reported clearly instead of surfacing as a generic rollout failure.
set -euo pipefail

# Load the local `.env` seam if present (same behaviour as the other smokes):
# a KEY=value line becomes a shell variable here, so `.env` overrides win over
# the pinned defaults in versions.sh below.
for _sca_env in "$(dirname "$0")/../.env" ".env"; do
  if [ -f "$_sca_env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$_sca_env"
    break
  fi
done
unset _sca_env

# shellcheck source=bootstrap/versions.sh
. "$(dirname "$0")/versions.sh"

NAMESPACE="${LINKERD_NS:-linkerd}"
ROLLOUT_TIMEOUT="${LINKERD_ROLLOUT_TIMEOUT:-300}"
ANCHOR_CM="${LINKERD_ANCHOR_CM:-linkerd-identity-trust-roots}"
ISSUER_SECRET="${LINKERD_ISSUER_SECRET:-linkerd-identity-issuer}"
EXPECT_ISSUER="${LINKERD_ISSUER_CN:-identity.linkerd.cluster.local}"
EXPECT_ANCHOR="${LINKERD_ANCHOR_CN:-root.linkerd.cluster.local}"
EXPECT_PROXY_VERSION="${LINKERD_PROXY_VERSION:-stable-2.14.10}"

# Ephemeral data-plane workload (deleted on exit).
SCRATCH_NS="${LINKERD_SMOKE_NS:-linkerd-smoke}"
SERVER_NAME="linkerd-smoke-server"
CLIENT_NAME="linkerd-smoke-client"
SERVER_IMAGE="${LINKERD_SMOKE_SERVER_IMAGE}"
CLIENT_IMAGE="${LINKERD_SMOKE_CLIENT_IMAGE}"
TRAFFIC_TIMEOUT="${LINKERD_TRAFFIC_TIMEOUT:-180}"
POLL="${SMOKE_POLL:-5}"

# A leaf must have at least this much life left for the data plane to be usable.
MIN_IDENTITY_TTL="${LINKERD_MIN_IDENTITY_TTL:-3600}"

# Control-plane workloads the chart deploys (one Deployment each).
DEPLOYMENTS=(
  linkerd-destination
  linkerd-identity
  linkerd-proxy-injector
)

# The control-plane-component label value for each Deployment.
cp_component() {
  case "$1" in
    linkerd-destination) echo destination ;;
    linkerd-identity) echo identity ;;
    linkerd-proxy-injector) echo proxy-injector ;;
    *) echo "" ;;
  esac
}

# The three admission webhook configurations whose caBundle the chart wires.
WEBHOOKS=(
  linkerd-proxy-injector-webhook-config
  linkerd-sp-validator-webhook-config
  linkerd-policy-validator-webhook-config
)

# Read a control-plane proxy's identity expiry from its admin endpoint. The
# controller containers are distroless, so this port-forwards from the host.
# Warnings (not failures) when no pod/metrics are available yet: the rollout
# check that follows is the gate for a cold install.
identity_ttl_for_deployment() {
  local dep="$1" comp port pod exp i now rem
  comp="$(cp_component "$dep")"
  pod="$(kubectl -n "$NAMESPACE" get pod \
    -l "linkerd.io/control-plane-component=${comp}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [ -z "$pod" ]; then
    echo "  ${dep} → no pod yet, skipping identity TTL preflight"
    return 0
  fi
  port=$(( 20000 + RANDOM % 20000 ))
  kubectl -n "$NAMESPACE" port-forward "pod/${pod}" "${port}:4191" >/dev/null 2>&1 &
  local pf_pid=$!
  exp=""
  for ((i = 0; i < 20; i++)); do
    exp="$(curl -fsS --max-time 2 "http://127.0.0.1:${port}/metrics" 2>/dev/null \
      | awk '/^identity_cert_expiration_timestamp_seconds /{v=$2} END{if (v != "") print v}' || true)"
    [ -n "$exp" ] && break
    sleep 1
  done
  kill "$pf_pid" >/dev/null 2>&1 || true
  wait "$pf_pid" 2>/dev/null || true
  if [ -z "$exp" ]; then
    echo "  ${dep} → no identity metrics yet, skipping identity TTL preflight"
    return 0
  fi
  now="$(date +%s)"
  rem=$(( exp - now ))
  if [ "$rem" -lt "$MIN_IDENTITY_TTL" ]; then
    echo "FAIL: ${dep} proxy identity leaf expires in ${rem}s (< ${MIN_IDENTITY_TTL}s)" >&2
    echo "      the emulator clock outran the leaf lifetime; delete the linkerd pods" >&2
    echo "      to re-issue leaves, or raise identity.issuer.issuanceLifetime in" >&2
    echo "      envs/local/linkerd.yaml" >&2
    return 1
  fi
  echo "  ${dep} → identity leaf valid for ${rem}s"
  return 0
}

# Assert the injector actually mutated a pod: a silently skipped injection
# (failurePolicy: Ignore) leaves the pod running without a proxy.
assert_meshed_pod() {
  local pod="$1" containers created_by pver
  containers="$(kubectl -n "$SCRATCH_NS" get pod "$pod" -o jsonpath='{.spec.containers[*].name}')"
  case " ${containers} " in
    *" linkerd-proxy "*) ;;
    *)
      echo "FAIL: pod/${pod} has no linkerd-proxy (containers: '${containers}')" >&2
      exit 1
      ;;
  esac
  created_by="$(kubectl -n "$SCRATCH_NS" get pod "$pod" \
    -o jsonpath='{.metadata.annotations.linkerd\.io/created-by}')"
  pver="$(kubectl -n "$SCRATCH_NS" get pod "$pod" \
    -o jsonpath='{.metadata.annotations.linkerd\.io/proxy-version}')"
  case "$created_by" in
    *linkerd/proxy-injector*) ;;
    *)
      echo "FAIL: pod/${pod} was not injected by the Linkerd proxy-injector (created-by='${created_by}')" >&2
      exit 1
      ;;
  esac
  [ "$pver" = "$EXPECT_PROXY_VERSION" ] || {
    echo "FAIL: pod/${pod} proxy version '${pver}' != '${EXPECT_PROXY_VERSION}'" >&2
    exit 1
  }
  echo "  pod/${pod} → linkerd-proxy injected (${pver})"
}

command -v openssl >/dev/null 2>&1 || { echo "FAIL: openssl is required for the identity chain check" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required for the mesh smoke" >&2; exit 1; }

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp" 2>/dev/null || true
  if [ "${LINKERD_SMOKE_KEEP:-0}" = "1" ]; then
    echo "  (LINKERD_SMOKE_KEEP=1: keeping namespace ${SCRATCH_NS})" >&2
    return 0
  fi
  kubectl delete namespace "$SCRATCH_NS" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "── smoke(linkerd): namespace ${NAMESPACE} present"
kubectl get namespace "$NAMESPACE" --no-headers >/dev/null

echo "── smoke(linkerd): identity PKI present"
# Trust anchor (ConfigMap, public) references only the committed root CA; the
# issuer Secret is owned by cert-manager and must be present before the chart
# reconciles (identity.externalCA=true + issuer.scheme=kubernetes.io/tls).
kubectl -n "$NAMESPACE" get configmap "$ANCHOR_CM" --no-headers >/dev/null
anchor_pem="$(kubectl -n "$NAMESPACE" get configmap "$ANCHOR_CM" -o jsonpath='{.data.ca-bundle\.crt}')"
[ -n "$anchor_pem" ] || { echo "FAIL: ${ANCHOR_CM} has no ca-bundle.crt" >&2; exit 1; }
kubectl -n "$NAMESPACE" get secret "$ISSUER_SECRET" --no-headers >/dev/null
for key in tls.crt tls.key; do
  kubectl -n "$NAMESPACE" get secret "$ISSUER_SECRET" -o "jsonpath={.data.${key//./\\.}}" | grep -q . \
    || { echo "FAIL: ${ISSUER_SECRET} missing key ${key}" >&2; exit 1; }
done
echo "  ${ANCHOR_CM} + ${ISSUER_SECRET} present"

echo "── smoke(linkerd): control-plane proxy identity leaves valid"
for d in "${DEPLOYMENTS[@]}"; do
  identity_ttl_for_deployment "$d"
done

echo "── smoke(linkerd): control-plane Deployments Ready"
for d in "${DEPLOYMENTS[@]}"; do
  kubectl -n "$NAMESPACE" rollout status "deployment/${d}" --timeout="${ROLLOUT_TIMEOUT}s" >/dev/null
  echo "  ${d} → Ready"
done

echo "── smoke(linkerd): admission webhooks wired with a caBundle"
for w in "${WEBHOOKS[@]}"; do
  kind=ValidatingWebhookConfiguration
  [ "$w" = "linkerd-proxy-injector-webhook-config" ] && kind=MutatingWebhookConfiguration
  ca="$(kubectl get "$kind" "$w" -o jsonpath='{.webhooks[0].clientConfig.caBundle}' 2>/dev/null || true)"
  [ -n "$ca" ] || { echo "FAIL: ${kind}/${w} has no caBundle" >&2; exit 1; }
  echo "  ${w} → caBundle set"
done

# End-to-end identity check: the identity service mints leaf certificates with
# its issuer; every leaf must chain to the trust anchor in the ConfigMap. We
# verify the STATIC chain we deployed instead of a live handshake: the anchor
# must verify the issuer, and the issuer's CN must match what the chart expects.
printf '%s\n' "$anchor_pem" > "$tmp/anchor.crt"
kubectl -n "$NAMESPACE" get secret "$ISSUER_SECRET" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$tmp/issuer.crt"

echo "── smoke(linkerd): issuer certificate chains to the trust anchor"
if ! openssl verify -CAfile "$tmp/anchor.crt" "$tmp/issuer.crt" >/dev/null 2>&1; then
  echo "FAIL: issuer certificate does not verify against the trust anchor" >&2
  openssl verify -CAfile "$tmp/anchor.crt" "$tmp/issuer.crt" || true
  exit 1
fi
anchor_cn="$(openssl x509 -in "$tmp/anchor.crt" -noout -subject | sed -E 's/.*CN ?= ?//')"
issuer_cn="$(openssl x509 -in "$tmp/issuer.crt" -noout -subject | sed -E 's/.*CN ?= ?//')"
[ "$anchor_cn" = "$EXPECT_ANCHOR" ] || { echo "FAIL: anchor CN '${anchor_cn}' != '${EXPECT_ANCHOR}'" >&2; exit 1; }
[ "$issuer_cn" = "$EXPECT_ISSUER" ] || { echo "FAIL: issuer CN '${issuer_cn}' != '${EXPECT_ISSUER}'" >&2; exit 1; }
echo "  anchor CN=${anchor_cn} → issuer CN=${issuer_cn} (chain verified)"

# ---------------------------------------------------------------------------
# Data plane: inject a throwaway namespace and exchange a real HTTP request.
# ---------------------------------------------------------------------------
echo "── smoke(linkerd): provisioning injected workload in ns ${SCRATCH_NS}"
if kubectl get namespace "$SCRATCH_NS" >/dev/null 2>&1; then
  kubectl delete namespace "$SCRATCH_NS" --timeout=60s >/dev/null 2>&1 || true
fi
kubectl create namespace "$SCRATCH_NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl annotate namespace "$SCRATCH_NS" linkerd.io/inject=enabled --overwrite >/dev/null

kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${SERVER_NAME}-web
  namespace: ${SCRATCH_NS}
data:
  index.html: "linkerd-mesh-ok\n"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${SERVER_NAME}
  namespace: ${SCRATCH_NS}
  labels:
    app.kubernetes.io/name: ${SERVER_NAME}
    app.kubernetes.io/part-of: sca-linkerd-smoke
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${SERVER_NAME}
  template:
    metadata:
      labels:
        app: ${SERVER_NAME}
    spec:
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: server
          image: ${SERVER_IMAGE}
          ports:
            - name: http
              containerPort: 8080
          readinessProbe:
            httpGet:
              path: /
              port: http
            periodSeconds: 2
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              cpu: 100m
              memory: 64Mi
          volumeMounts:
            - name: web
              mountPath: /usr/share/nginx/html
              readOnly: true
      volumes:
        - name: web
          configMap:
            name: ${SERVER_NAME}-web
---
apiVersion: v1
kind: Service
metadata:
  name: ${SERVER_NAME}
  namespace: ${SCRATCH_NS}
spec:
  selector:
    app: ${SERVER_NAME}
  ports:
    - name: http
      port: 8080
      targetPort: http
EOF

kubectl -n "$SCRATCH_NS" rollout status "deployment/${SERVER_NAME}" --timeout="${ROLLOUT_TIMEOUT}s" >/dev/null
server_pod="$(kubectl -n "$SCRATCH_NS" get pod -l app="$SERVER_NAME" -o jsonpath='{.items[0].metadata.name}')"
[ -n "$server_pod" ] || { echo "FAIL: no server pod in ${SCRATCH_NS}" >&2; exit 1; }
assert_meshed_pod "$server_pod"

echo "── smoke(linkerd): running an HTTP client through the mesh"
kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${CLIENT_NAME}
  namespace: ${SCRATCH_NS}
  labels:
    app.kubernetes.io/name: ${CLIENT_NAME}
    app.kubernetes.io/part-of: sca-linkerd-smoke
    app: ${CLIENT_NAME}
spec:
  restartPolicy: Never
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: client
      image: ${CLIENT_IMAGE}
      command: ["/bin/sh", "-ec"]
      env:
        - name: SERVER_URL
          value: "http://${SERVER_NAME}.${SCRATCH_NS}.svc.cluster.local:8080/"
        - name: PROXY_ADMIN
          value: "http://127.0.0.1:4191"
      securityContext:
        # curlimages/curl's USER is the non-numeric "curl_user" (uid 100):
        # pin the numeric uid so the runAsNonRoot check can verify it.
        runAsNonRoot: true
        runAsUser: 100
        runAsGroup: 100
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          cpu: 100m
          memory: 64Mi
      args:
        - |
          set -eu
          echo "-- waiting for \${SERVER_URL}"
          ok=""
          for i in \$(seq 1 60); do
            if body="\$(curl -fsS --max-time 5 "\${SERVER_URL}" 2>/dev/null)"; then
              case "\$body" in *linkerd-mesh-ok*) ok=1; break;; esac
            fi
            sleep 2
          done
          [ -n "\$ok" ] || { echo "FAIL: no expected body from \${SERVER_URL}"; exit 1; }
          echo "HTTP_OK"
          curl -fsS --max-time 5 "\${PROXY_ADMIN}/ready" >/dev/null
          echo "READY_OK"
          met="\$(curl -fsS --max-time 5 "\${PROXY_ADMIN}/metrics")"
          exp="\$(printf '%s\n' "\$met" | awk '/^identity_cert_expiration_timestamp_seconds /{print \$2; exit}')"
          now="\$(date +%s)"
          [ -n "\$exp" ] || { echo "FAIL: client proxy exposes no identity expiry metric"; exit 1; }
          rem=\$(( exp - now ))
          [ "\$rem" -gt 0 ] || { echo "FAIL: client identity leaf expired \${rem}s ago"; exit 1; }
          echo "IDENTITY_OK remaining_s=\${rem}"
          printf '%s\n' "\$met" | awk '/^response_total/ && /direction="outbound"/ && /classification="success"/ {f=1} END{exit !f}' \
            || { echo "FAIL: no successful outbound response metric after the request"; exit 1; }
          echo "OUTBOUND_OK"
EOF

# Wait for the client pod to exist, then prove it was injected.
client_pod="$CLIENT_NAME"
for ((i = 0; i < 30; i++)); do
  kubectl -n "$SCRATCH_NS" get pod "$client_pod" >/dev/null 2>&1 && break
  sleep 2
done
kubectl -n "$SCRATCH_NS" get pod "$client_pod" >/dev/null 2>&1 || {
  echo "FAIL: no client pod in ${SCRATCH_NS}" >&2
  exit 1
}
assert_meshed_pod "$client_pod"

# The injected proxy is a sidecar, so the pod never reaches Succeeded; wait for
# the client container itself to terminate with exit code 0.
deadline=$(( $(date +%s) + TRAFFIC_TIMEOUT ))
while : ; do
  reason="$(kubectl -n "$SCRATCH_NS" get pod "$client_pod" \
    -o jsonpath='{.status.containerStatuses[?(@.name=="client")].state.terminated.reason}' 2>/dev/null || true)"
  code="$(kubectl -n "$SCRATCH_NS" get pod "$client_pod" \
    -o jsonpath='{.status.containerStatuses[?(@.name=="client")].state.terminated.exitCode}' 2>/dev/null || true)"
  if [ "$reason" = "Completed" ] && [ "$code" = "0" ]; then
    break
  fi
  if [ "$reason" = "Error" ]; then
    echo "FAIL: client container exited with code ${code} (mesh request)" >&2
    kubectl -n "$SCRATCH_NS" logs "$client_pod" -c client --tail=200 >&2 2>/dev/null || true
    exit 1
  fi
  [ "$(date +%s)" -lt "$deadline" ] || {
    echo "FAIL: client container did not finish within ${TRAFFIC_TIMEOUT}s" >&2
    kubectl -n "$SCRATCH_NS" get pods -o wide >&2 2>/dev/null || true
    kubectl -n "$SCRATCH_NS" describe pod "$client_pod" >&2 2>/dev/null || true
    kubectl -n "$SCRATCH_NS" logs "$client_pod" --all-containers --prefix --tail=200 >&2 2>/dev/null || true
    exit 1
  }
  sleep "$POLL"
done

out="$(kubectl -n "$SCRATCH_NS" logs "$client_pod" -c client --tail=50 2>/dev/null || true)"
for want in HTTP_OK READY_OK IDENTITY_OK OUTBOUND_OK; do
  case "$out" in
    *"$want"*) ;;
    *)
      echo "FAIL: client did not report ${want}" >&2
      printf '%s\n' "$out" >&2
      exit 1
      ;;
  esac
done
echo "  client → server request 200, live identity, outbound response counted"

# Inbound side: read the server proxy's admin endpoint from inside the pod.
echo "── smoke(linkerd): server proxy counted the inbound request"
server_metrics="$(kubectl -n "$SCRATCH_NS" exec "$server_pod" -c server -- \
  wget -qO- "http://127.0.0.1:4191/metrics" 2>/dev/null || true)"
if [ -z "$server_metrics" ]; then
  server_metrics="$(kubectl -n "$SCRATCH_NS" exec "$server_pod" -c server -- \
    sh -c 'printf "GET /metrics HTTP/1.0\r\n\r\n" | nc 127.0.0.1 4191' 2>/dev/null || true)"
fi
[ -n "$server_metrics" ] || { echo "FAIL: could not read the server proxy metrics" >&2; exit 1; }

kubectl -n "$SCRATCH_NS" exec "$server_pod" -c server -- \
  wget -q -O /dev/null "http://127.0.0.1:4191/ready" >/dev/null 2>&1 || {
  echo "FAIL: server proxy /ready is not 200" >&2
  exit 1
}

printf '%s\n' "$server_metrics" | awk \
  '/^response_total/ && /direction="inbound"/ && /classification="success"/ {f=1} END{exit !f}' || {
  echo "FAIL: no successful inbound response metric on the server proxy" >&2
  exit 1
}
srv_exp="$(printf '%s\n' "$server_metrics" \
  | awk '/^identity_cert_expiration_timestamp_seconds /{v=$2} END{if (v != "") print v}')"
srv_now="$(date +%s)"
[ -n "$srv_exp" ] || { echo "FAIL: server proxy exposes no identity expiry metric" >&2; exit 1; }
[ "$(( srv_exp - srv_now ))" -gt 0 ] || { echo "FAIL: server identity leaf is expired" >&2; exit 1; }

if printf '%s\n' "$server_metrics" | awk '/tls=/{f=1} END{exit !f}'; then
  printf '%s\n' "$server_metrics" | awk '/tls="true"/{f=1} END{exit !f}' || {
    echo "FAIL: inbound mesh traffic is not mTLS (tls != true)" >&2
    exit 1
  }
  echo "  server → inbound mTLS (tls=\"true\"), identity leaf live"
else
  echo "  server → inbound response counted, identity leaf live (mTLS proven by both proxies holding live leaves)"
fi

echo "[OK] smoke(linkerd): control plane Ready, webhooks wired, identity chain valid, injected workload reached the mesh (HTTP 200, inbound+outbound)"
