#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# render-served-apps.sh — push a rendered `argocd/apps-local.yaml` into the local
# git serve so the app-of-apps root Application can render the ApplicationSet
# straight from the served content. The repo keeps the {{GIT_REPO_URL}} /
# {{GIT_TARGET_BRANCH}} placeholders (the `make bootstrap` seam and the
# published-repo path); this helper substitutes them ONLY in the served copy,
# committing it onto the serve branch so the served file is valid YAML.
# Local tooling only — not part of the ArgoCD platform catalog.
# Called by `make local-git-up` / `make local-git-update`.
# Usage: render-served-apps.sh <destination>
#   <destination>  git remote for the serve (git:// URL or local bare path)
set -euo pipefail

dest="${1:-}"
[ -n "${dest}" ] || { echo 'usage: render-served-apps.sh <destination>' >&2; exit 2; }

# Seam values: explicit env first, then the .env seam file (for direct invocations).
branch="${GIT_TARGET_BRANCH:-}"
repo_url="${GIT_REPO_URL:-}"
if [ -z "${branch}" ] || [ -z "${repo_url}" ]; then
  # shellcheck disable=SC1091
  . ./.env 2>/dev/null || true
fi
branch="${branch:-${GIT_TARGET_BRANCH:-main}}"
repo_url="${repo_url:-${GIT_REPO_URL:-}}"
[ -n "${repo_url}" ] || { echo 'ERROR: GIT_REPO_URL is empty — run make local-git-up first' >&2; exit 1; }

src="argocd/apps-local.yaml"
[ -f "${src}" ] || { echo "ERROR: ${src} is missing" >&2; exit 1; }

tmp="$(mktemp -d)"
work="${tmp}/checkout"
cleanup() {
  git worktree remove --force "${work}" >/dev/null 2>&1 || true
  rm -rf "${tmp}"
}
trap cleanup EXIT

git worktree add --detach "${work}" HEAD >/dev/null

sed -e "s|{{GIT_REPO_URL}}|${repo_url}|g" \
    -e "s|{{GIT_TARGET_BRANCH}}|${branch}|g" \
    "${src}" > "${work}/${src}"

git -C "${work}" add "${src}"
git -C "${work}" -c user.name='sca local serve' -c user.email='local@serve.invalid' \
    commit -m 'chore(local): render served ArgoCD manifests for git serve' --quiet

echo "── pushing rendered ${src} → ${dest} (refs/heads/${branch})"
git -C "${work}" push --force "${dest}" "HEAD:refs/heads/${branch}"