#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# prereqs.sh — Install the pinned platform CLI toolchain (kubectl, helm, kind).
#   1. Binaries already present at the pinned version are skipped (idempotent)
#   2. Downloads from official upstream release URLs with sha256 verification
#   3. Installs into INSTALL_DIR (default ~/.local/bin — no sudo required)
# Usage: make prereqs
set -euo pipefail

KUBECTL_VERSION="${KUBECTL_VERSION:-v1.36.4}"
HELM_VERSION="${HELM_VERSION:-v4.2.4}"
KIND_VERSION="${KIND_VERSION:-v0.32.0}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64 | arm64) ARCH="arm64" ;;
  *) echo "ERROR: unsupported architecture: ${ARCH}"; exit 1 ;;
esac

installed_version() {
  case "$1" in
    kubectl) kubectl version --client 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
    helm) helm version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
    kind) kind version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
  esac
}

download_verified() {
  local url="$1" sum_url="$2" dest="$3"
  local tmp; tmp="$(mktemp)"
  echo "── Downloading ${url}"
  curl -fsSL "$url" -o "$tmp"
  local expected; expected="$(curl -fsSL "$sum_url" | grep -oE '^[0-9a-f]{64}' | head -1)"
  [ -n "$expected" ] || { echo "ERROR: no sha256 published at ${sum_url}"; rm -f "$tmp"; exit 1; }
  echo "${expected}  ${tmp}" | sha256sum -c - >/dev/null || { echo "ERROR: checksum mismatch for ${url}"; rm -f "$tmp"; exit 1; }
  install -m 0755 "$tmp" "$dest"
  rm -f "$tmp"
}

mkdir -p "$INSTALL_DIR"
export PATH="${INSTALL_DIR}:${PATH}"

if [ "$(installed_version kubectl)" = "$KUBECTL_VERSION" ]; then
  echo "[OK] kubectl ${KUBECTL_VERSION} already installed"
else
  download_verified \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl.sha256" \
    "${INSTALL_DIR}/kubectl"
fi

if [ "$(installed_version helm)" = "$HELM_VERSION" ]; then
  echo "[OK] helm ${HELM_VERSION} already installed"
else
  tmp_tgz="$(mktemp --suffix=.tar.gz)"
  echo "── Downloading https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"
  curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" -o "$tmp_tgz"
  expected="$(curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz.sha256sum" | grep -oE '^[0-9a-f]{64}' | head -1)"
  [ -n "$expected" ] || expected="$(curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz.sha256" | grep -oE '^[0-9a-f]{64}' | head -1)"
  echo "${expected}  ${tmp_tgz}" | sha256sum -c - >/dev/null || { echo "ERROR: checksum mismatch for helm tarball"; rm -f "$tmp_tgz"; exit 1; }
  tar -xzf "$tmp_tgz" --strip-components=1 -C "$INSTALL_DIR" "linux-${ARCH}/helm"
  chmod 0755 "${INSTALL_DIR}/helm"
  rm -f "$tmp_tgz"
fi

if [ "$(installed_version kind)" = "$KIND_VERSION" ]; then
  echo "[OK] kind ${KIND_VERSION} already installed"
else
  download_verified \
    "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${ARCH}" \
    "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${ARCH}.sha256sum" \
    "${INSTALL_DIR}/kind"
fi

echo ""
echo "── Toolchain ──"
kubectl version --client
helm version --short
kind version

case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ;;
  *) echo ""; echo "NOTE: add ${INSTALL_DIR} to your PATH (e.g. export PATH=\"\$HOME/.local/bin:\$PATH\")" ;;
esac

echo ""
echo "Prerequisites ready. Next: make cluster-up"
