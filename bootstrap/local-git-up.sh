#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# local-git-up.sh — stand up the fully-local git serve for the local platform:
# an in-cluster git daemon (bootstrap/local-git-server.yaml) serving a bare
# mirror of this repo from the node filesystem (hostPath /srv), plus the .env
# seam pointing GIT_REPO_URL at it. Local ArgoCD then reconciles local content
# with zero dependency on GitHub; `make local-git-update` pushes the working
# tree into the serve. Works on any single-node cluster (the Floci EKS node
# included). See docs/ci-cd.md and .env.example.
# Usage: make local-git-up
set -euo pipefail

GIT_TARGET_BRANCH="${GIT_TARGET_BRANCH:-main}"
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

kubectl create namespace "${SERVE_NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f bootstrap/local-git-server.yaml >/dev/null
echo "── waiting for ${SERVE_POD} (git daemon, port ${PORT}) to be Running"
kubectl -n "${SERVE_NS}" wait --for=jsonpath='{.status.phase}'=Running "pod/${SERVE_POD}" --timeout=120s >/dev/null

# The pod mounts the node's /srv (hostPath), so stream the bare repo into it via
# the API server: no docker/kind node access needed, and it works on any
# single-node substrate.
if kubectl -n "${SERVE_NS}" exec "${SERVE_POD}" -- test -d /srv/sca-infra.git/objects >/dev/null 2>&1; then
  echo "[skip] bare repo already seeded on the node (/srv/sca-infra.git)"
else
  echo "── seeding bare repo into ${SERVE_POD}:/srv/sca-infra.git"
  tar -C .git-local -cf - sca-infra.git \
    | kubectl -n "${SERVE_NS}" exec -i "${SERVE_POD}" -- tar -C /srv -xf -
fi

# hostNetwork: the pod IP is the node IP, reachable from the host.
echo "── resolving the serve address"
serve_ip=""
for attempt in $(seq 1 30); do
  serve_ip="$(kubectl -n "${SERVE_NS}" get pod "${SERVE_POD}" -o jsonpath='{.status.podIP}' 2>/dev/null || true)"
  case "${serve_ip}" in
    *"."*)
      if [ "${serve_ip}" != "0.0.0.0" ]; then break; fi ;;
  esac
  serve_ip=""
  sleep 2
done
[ -n "${serve_ip}" ] || { echo "ERROR: cannot determine the git serve address (pod IP)"; exit 1; }
serve_url="git://${serve_ip}:${PORT}/sca-infra.git"

echo "── checking reachability of ${serve_url} from the host"
# The pod has no readiness probe and its first act is `apk add git-daemon`, so
# Running does not mean the daemon is listening yet: retry the handshake.
reachable=0
for attempt in $(seq 1 30); do
  if git ls-remote "${serve_url}" >/dev/null 2>&1; then
    reachable=1
    break
  fi
  sleep 2
done
[ "$reachable" -eq 1 ] || { echo "ERROR: cannot reach ${serve_url}"; exit 1; }

echo "── mirroring HEAD → serve (refs/heads/${GIT_TARGET_BRANCH})"
GIT_TARGET_BRANCH="${GIT_TARGET_BRANCH}" \
  "$(dirname "$0")/render-served-apps.sh" "${serve_url}"

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
