#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# render-served-apps.sh — push this repo's HEAD into the local git serve.
# The serve carries the repo **verbatim**: `make bootstrap` seeds the ArgoCD
# wiring (argocd/apps-<env>.yaml, argocd/kong-<env>.yaml) on the cluster directly
# with {{GIT_REPO_URL}}/{{GIT_TARGET_BRANCH}} resolved host-side, so nothing on
# the serve needs substitution — ArgoCD reconciles the served content as-is, and
# the generated component Applications read the same tree from the serve.
# Local tooling only — not part of the ArgoCD platform catalog.
# Called by `make local-git-up` / `make local-git-update`.
# Usage: render-served-apps.sh <destination>
#   <destination>  git remote for the serve (git:// URL or local bare path)
set -euo pipefail

dest="${1:-}"
[ -n "${dest}" ] || { echo 'usage: render-served-apps.sh <destination>' >&2; exit 2; }

# Seam values: explicit env first, then the .env seam file (for direct invocations).
branch="${GIT_TARGET_BRANCH:-}"
if [ -z "${branch}" ]; then
  # shellcheck disable=SC1091
  . ./.env 2>/dev/null || true
fi
branch="${branch:-${GIT_TARGET_BRANCH:-main}}"

echo "── pushing HEAD → ${dest} (refs/heads/${branch})"
git push --force "${dest}" "HEAD:refs/heads/${branch}"
