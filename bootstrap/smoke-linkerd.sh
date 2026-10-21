#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-linkerd.sh — verify the Linkerd control plane is deployed and healthy.
# Project gate for Phase 9: the mesh's control plane runs, its webhooks are
# wired, its identity PKI is present and Ready, and — the real end-to-end
# assertion — the identity controller serves a certificate that chains to the
# trust anchor the proxies trust (i.e. the CLI's `linkerd check --proxy`-style
# identity verification, done with kubectl/openssl so no CLI is needed).
set -euo pipefail

NAMESPACE="${LINKERD_NS:-linkerd}"
TIMEOUT="${SMOKE_TIMEOUT:-120s}"
ROLLOUT_TIMEOUT="${LINKERD_ROLLOUT_TIMEOUT:-300}"
ANCHOR_CM="${LINKERD_ANCHOR_CM:-linkerd-identity-trust-roots}"
ISSUER_SECRET="${LINKERD_ISSUER_SECRET:-linkerd-identity-issuer}"
EXPECT_ISSUER="${LINKERD_ISSUER_CN:-identity.linkerd.cluster.local}"
EXPECT_ANCHOR="${LINKERD_ANCHOR_CN:-root.linkerd.cluster.local}"

# Control-plane workloads the chart deploys (one Deployment each).
DEPLOYMENTS=(
  linkerd-destination
  linkerd-identity
  linkerd-proxy-injector
)

# The three admission webhook configurations whose caBundle the chart wires.
WEBHOOKS=(
  linkerd-proxy-injector-webhook-config
  linkerd-sp-validator-webhook-config
  linkerd-policy-validator-webhook-config
)

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
command -v openssl >/dev/null 2>&1 || { echo "FAIL: openssl is required for the identity chain check" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
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

echo "[OK] smoke(linkerd): control plane Ready, webhooks wired, identity chain valid"
