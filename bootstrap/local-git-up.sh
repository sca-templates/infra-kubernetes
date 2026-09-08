#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# local-git-up.sh — stand up the fully-local git serve for the local kind
# platform: an in-cluster git daemon (bootstrap/local-git-server.yaml) serving
# a bare mirror of this repo on the kind node network, plus the .env seam
# pointing GIT_REPO_URL at it. Local ArgoCD then reconciles local content with
# zero dependency on GitHub; `make local-git-update` pushes the working tree
# into the serve. See docs/ci-cd.md and .env.example.
# Usage: make local-git-up
set -euo pipefail

GIT_TARGET_BRANCH="${GIT_TARGET_BRANCH:-main}"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-sca-local}"
BARE=".git-local/sca-infra.git"
PORT=9418
SERVE_POD="git-local-serve"
SERVE_NS="git-serve"

mkdir -p .git-local

if [ -d "${BARE}/objects" ]; then
  echo "[skip] local bare mirror already exists: ${BARE}"
else
  echo "── creating local bare mirror of the working repo: ${BARE}"
  git clone --bare . "${BARE}" >/dev/null
fi
git --git-dir="${BARE}" rev-parse --is-bare-repository >/dev/null

node="${KIND_CLUSTER_NAME}-control-plane"
if docker exec "${node}" test -d /srv/sca-infra.git >/dev/null 2>&1; then
  echo "[skip] bare repo already seeded on node /srv/sca-infra.git"
else
  echo "── seeding bare repo onto kind node (${node}:/srv/sca-infra.git)"
  docker exec "${node}" sh -c 'mkdir -p /srv'
  docker cp "${BARE}" "${node}:/srv/sca-infra.git" >/dev/null
fi

sed "s|nodeName: sca-local-control-plane|nodeName: ${node}|" \
  bootstrap/local-git-server.yaml | kubectl apply -f - >/dev/null
echo "── waiting for git-local-serve (git daemon, port ${PORT}) to be Ready"
kubectl -n "${SERVE_NS}" wait --for=condition=Ready "pod/${SERVE_POD}" --timeout=120s >/dev/null

node_ip="$(kubectl get node "${node}" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')"
case "${node_ip}" in
  *"."*) ;;
  *) echo "ERROR: cannot determine the kind node IP"; exit 1 ;;
esac
serve_url="git://${node_ip}:${PORT}/sca-infra.git"

echo "── checking reachability of ${serve_url} from the host"
git ls-remote "${serve_url}" >/dev/null 2>&1 || { echo "ERROR: cannot reach ${serve_url}"; exit 1; }

upsert_env() {
  local key="$1" value="$2"
  if grep -q "^${key}=" .env 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
}

echo "── writing .env seam"
upsert_env GIT_REPO_URL "${serve_url}"
upsert_env GIT_TARGET_BRANCH "${GIT_TARGET_BRANCH}"

echo ""
echo "[OK] local git serve ready: ${serve_url} (tracking refs/heads/${GIT_TARGET_BRANCH})"
echo "Next: make bootstrap ENV=local   (ArgoCD tracks the local serve)"
echo "      make local-git-update      (after each commit: mirror HEAD → serve)"