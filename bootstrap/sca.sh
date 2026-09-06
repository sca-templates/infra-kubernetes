#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# sca.sh — the sca platform CLI. POSIX-first local tooling for anyone on Linux
# (any distro), macOS and WSL2; Windows-native is out of scope (use WSL2).
#
#   sca prereqs   install the pinned CLI toolchain (kubectl, helm, kind) into
#                 ~/.local/bin — idempotent, sha256-verified, no sudo
#   sca doctor    read-only health: toolchain, PATH, docker, git, cluster,
#                 ArgoCD apps, the .env seam and the tracked git source
#   sca version   print the pinned toolchain versions
#   sca help      this help
#
# Thinner entry point than the Makefile wrapper: `make prereqs`, `make doctor`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/versions.sh"

INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-sca-local}"

ok()   { printf '[OK]   %s\n' "$*"; }
skip() { printf '[skip] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; }
dlog() { printf '%s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

detect_os_arch() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW* | MSYS* | CYGWIN*)
      die "Windows nativo no esta soportado. Usa WSL2 (este repo es POSIX).";;
    *) die "Sistema no soportado: $(uname -s)" ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) ARCH="amd64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    *) die "Arquitectura no soportada: $(uname -m)" ;;
  esac
}

installed_version() {
  case "$1" in
    kubectl) kubectl version --client 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
    helm)    helm version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
    kind)    kind version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
  esac
}

download_verified() {
  local url="$1" sum_url="$2" dest="$3"
  local tmp expected
  tmp="$(mktemp)"
  dlog "── Downloading ${url}"
  curl -fsSL "$url" -o "$tmp" || { warn "download failed for ${url}"; rm -f "$tmp"; return 1; }
  expected="$(curl -fsSL "$sum_url" | grep -oE '^[0-9a-f]{64}' | head -1)"
  [ -n "$expected" ] || { warn "no sha256 published at ${sum_url}"; rm -f "$tmp"; return 1; }
  echo "${expected}  ${tmp}" | sha256sum -c - >/dev/null 2>&1 || { warn "checksum mismatch for ${url}"; rm -f "$tmp"; return 1; }
  install -m 0755 "$tmp" "$dest"
  rm -f "$tmp"
}

install_one() {
  local tool="$1"
  local current ver="$2"
  current="$(installed_version "$tool")"
  if [ "$current" = "$ver" ]; then
    skip "${tool} ${ver} already installed"
    return 0
  fi
  case "$tool" in
    kubectl)
      download_verified \
        "https://dl.k8s.io/release/${ver}/bin/${OS}/${ARCH}/kubectl" \
        "https://dl.k8s.io/release/${ver}/bin/${OS}/${ARCH}/kubectl.sha256" \
        "${INSTALL_DIR}/kubectl" || return 1 ;;
    helm)
      if download_verified \
        "https://get.helm.sh/helm-${ver}-${OS}-${ARCH}.tar.gz" \
        "https://get.helm.sh/helm-${ver}-${OS}-${ARCH}.tar.gz.sha256sum" \
        "${INSTALL_DIR}/.helm.tgz"; then
        tar -xzf "${INSTALL_DIR}/.helm.tgz" --strip-components=1 -C "${INSTALL_DIR}" "${OS}-${ARCH}/helm"
        chmod 0755 "${INSTALL_DIR}/helm"
        rm -f "${INSTALL_DIR}/.helm.tgz"
      else
        rm -f "${INSTALL_DIR}/.helm.tgz"
        return 1
      fi ;;
    kind)
      download_verified \
        "https://github.com/kubernetes-sigs/kind/releases/download/${ver}/kind-${OS}-${ARCH}" \
        "https://github.com/kubernetes-sigs/kind/releases/download/${ver}/kind-${OS}-${ARCH}.sha256sum" \
        "${INSTALL_DIR}/kind" || return 1 ;;
  esac
  ok "${tool} ${ver} installed"
}

check_external() {
  if command -v git >/dev/null 2>&1; then ok "git present: $(git --version)"
  else warn "git missing"; dlog "      hint: Linux: apt install git · macOS: brew install git"; fi
  if command -v docker >/dev/null 2>&1; then ok "docker present"
  else warn "docker missing — required for kind."; dlog "      hint: Linux: install via docker.com (or apt docker.io) · macOS: Docker Desktop"; fi
}

cmd_prereqs() {
  detect_os_arch
  [ "${WSL_DISTRO_NAME:-}" ] && dlog "note: WSL2 detected — this is Linux; the platform runs inside the distro."
  ok "OS=${OS} ARCH=${ARCH} (pinned: kubectl ${KUBECTL_VERSION} · helm ${HELM_VERSION} · kind ${KIND_VERSION})"
  if [ "${OS}" = "darwin" ]; then
    warn "darwin install path is verified by upstream URL pattern only (not tested on hardware yet)"
  fi

  mkdir -p "${INSTALL_DIR}"
  export PATH="${INSTALL_DIR}:${PATH}"

  install_one kubectl "${KUBECTL_VERSION}"
  install_one helm "${HELM_VERSION}"
  install_one kind "${KIND_VERSION}"

  dlog ""
  dlog "── Toolchain ──"
  kubectl version --client
  helm version --short
  kind version

  check_external

  case ":${PATH}:" in
    *":${INSTALL_DIR}:"*) ;;
    *) dlog ""; dlog "NOTE: add ${INSTALL_DIR} to your PATH (e.g. export PATH=\"\$HOME/.local/bin:\$PATH\")" ;;
  esac

  dlog ""
  dlog "Prerequisites ready. Next: make cluster-up"
}

load_env_seam() {
  if [ -f ".env" ]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
  fi
}

check_argocd_apps() {
  local line name sync health bad=""
  while read -r name sync health _; do
    [ -n "$name" ] || continue
    case "${sync}:${health}" in
      *:Degraded | *:Missing) fail "app ${name}: ${sync}/${health}" ; bad=1 ;;
      Synced:Healthy) ok "app ${name}: ${sync}/${health}" ;;
      *) warn "app ${name}: ${sync}/${health}"; bad=1 ;;
    esac
  done < <(kubectl get applications -n argocd --no-headers 2>/dev/null || true)
  if [ -z "${bad:-}" ] && ! kubectl get applications -n argocd --no-headers 2>/dev/null | grep -q .; then
    dlog "      (no ArgoCD applications yet)"
  fi
}

check_git_source() {
  local url="$1"
  case "$url" in
    git://*)
      if GIT_CONNECT_TIMEOUT=6 git ls-remote "${url}" HEAD >/dev/null 2>&1; then
        ok "git source reachable: ${url}"
      else
        fail "git source NOT reachable: ${url} (local git serve down?) — run: make local-git-up"
      fi ;;
    https://*)
      dlog "      (git source is ${url} — reachability is verified in CI; local clone not fetched by doctor)" ;;
    *) dlog "      (git source is ${url})" ;;
  esac
}

cmd_doctor() {
  detect_os_arch
  load_env_seam
  local GIT_REPO_URL_EF="${GIT_REPO_URL:-https://github.com/sca-templates/infra-kubernetes}"
  local GIT_TARGET_BRANCH_EF="${GIT_TARGET_BRANCH:-main}"
  ok "doctor ${OS}/${ARCH}"

  dlog ""
  dlog "── Toolchain (pins: kubectl ${KUBECTL_VERSION} · helm ${HELM_VERSION} · kind ${KIND_VERSION}) ──"
  for tool in kubectl helm kind; do
    local v
    v="$(installed_version "$tool")"
    if [ -n "$v" ]; then
      if [ "$v" = "$(case "$tool" in kubectl) echo "$KUBECTL_VERSION";; helm) echo "$HELM_VERSION";; kind) echo "$KIND_VERSION";; esac)" ]; then
        ok "${tool} ${v}"
      else warn "${tool} ${v} (pinned $(case "$tool" in kubectl) echo "$KUBECTL_VERSION";; helm) echo "$HELM_VERSION";; kind) echo "$KIND_VERSION";; esac)) — run: make prereqs"; fi
    else
      warn "${tool} not installed — run: make prereqs"
    fi
  done

  dlog ""
  dlog "── Environment ──"
  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then ok "docker reachable"
    else warn "docker not running (daemon isn't reachable)"; fi
  else warn "docker not installed"; fi
  case ":${PATH}:" in
    *":${INSTALL_DIR}:"*) ok "PATH includes ${INSTALL_DIR}" ;;
    *) warn "PATH does not include ${INSTALL_DIR}" ;;
  esac
  if [ -f ".env" ]; then ok ".env seam present"
  else warn ".env missing — make uses GitHub/main defaults"; fi
  dlog "      seam: GIT_REPO_URL=${GIT_REPO_URL_EF} · GIT_TARGET_BRANCH=${GIT_TARGET_BRANCH_EF} · KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME}"

  dlog ""
  dlog "── Git source ──"
  check_git_source "${GIT_REPO_URL_EF}"

  dlog ""
  dlog "── Cluster & ArgoCD ──"
  if kubectl cluster-info --request-timeout=5s >/dev/null 2>&1; then
    ok "cluster reachable ($(kubectl config current-context))"
    if kubectl get namespace argocd --request-timeout=5s >/dev/null 2>&1; then
      check_argocd_apps
    else
      dlog "      (ArgoCD not installed yet — run: make bootstrap)"
    fi
  else
    fail "no cluster reachable — run: make cluster-up && make bootstrap"
  fi

  dlog ""
  dlog "── Summary ──"
  dlog "doctor finished (read-only; it never mutates your machine or cluster)"
}

cmd_version() {
  printf 'kubectl %s\nhelm %s\nkind %s\n' "${KUBECTL_VERSION}" "${HELM_VERSION}" "${KIND_VERSION}"
}

cmd_help() {
  dlog "sca — infra-kubernetes platform CLI (POSIX)"
  dlog ""
  dlog "  sca prereqs   install pinned kubectl/helm/kind into ~/.local/bin (idempotent, no sudo)"
  dlog "  sca doctor    read-only health: toolchain, PATH, docker, git, cluster, ArgoCD apps, seam"
  dlog "  sca version   print pinned toolchain versions"
  dlog "  sca help      this help"
  dlog ""
  dlog "Windows: run inside WSL2. macOS/Linux supported."
}

main() {
  local cmd="${1:-help}"
  case "$cmd" in
    prereqs) cmd_prereqs ;;
    doctor) cmd_doctor ;;
    version) cmd_version ;;
    help | --help | -h) cmd_help ;;
    *) die "unknown command '${cmd}' — see sca help" ;;
  esac
}

main "$@"