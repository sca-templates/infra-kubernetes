#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-cert-manager.sh — request an in-namespace leaf Certificate from the
# sca-ca ClusterIssuer and confirm it reaches Ready. Selective smoke for the
# cert-manager component; driven by `make smoke COMPONENT=cert-manager`
# (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${SMOKE_NAMESPACE:-cert-manager-smoke}"
CERT_NAME="${SMOKE_CERT_NAME:-smoke-leaf}"
SECRET_NAME="${SMOKE_SECRET_NAME:-smoke-leaf-tls}"
TIMEOUT="${SMOKE_TIMEOUT:-120s}"

cleanup() {
  if [ "${SMOKE_KEEP:-0}" = "1" ]; then
    echo "── smoke namespace kept (SMOKE_KEEP=1): ${NAMESPACE}"
  else
    kubectl delete namespace "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "── smoke(cert-manager): leaf Certificate from sca-ca"
kubectl wait --for=condition=Ready clusterissuer/sca-ca --timeout="$TIMEOUT"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${CERT_NAME}
  namespace: ${NAMESPACE}
spec:
  secretName: ${SECRET_NAME}
  dnsNames:
    - smoke.sca
  issuerRef:
    name: sca-ca
    kind: ClusterIssuer
EOF

echo "── waiting for Certificate/${CERT_NAME} Ready (timeout ${TIMEOUT})"
kubectl wait --for=condition=Ready "certificate/${CERT_NAME}" -n "$NAMESPACE" --timeout="$TIMEOUT"

echo "── verifying tls secret holds a valid PEM certificate"
data="$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}')"
pem="$(printf '%s' "$data" | base64 --decode 2>/dev/null || true)"
case "$pem" in
  "-----BEGIN CERTIFICATE-----"*) ;;
  *) echo "FAIL: secret ${SECRET_NAME} has no PEM certificate" >&2; exit 1 ;;
esac

echo "[OK] smoke(cert-manager): sca-ca issued a leaf Certificate (Ready)"