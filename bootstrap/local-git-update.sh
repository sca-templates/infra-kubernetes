#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# local-git-update.sh — mirror the working tree into the local git serve so the
# local ArgoCD picks it up without pushing to GitHub. After every local commit:
#   make local-git-update
# Usage: make local-git-update [GIT_TARGET_BRANCH=<branch>]
set -euo pipefail

GIT_TARGET_BRANCH="${GIT_TARGET_BRANCH:-main}"
GIT_REPO_URL="${GIT_REPO_URL:-}"

[ -n "$GIT_REPO_URL" ] || { echo 'ERROR: GIT_REPO_URL is empty — run make local-git-up first'; exit 1; }

echo "── mirroring HEAD → ${GIT_TARGET_BRANCH} on ${GIT_REPO_URL}"
git push --force "${GIT_REPO_URL}" "HEAD:refs/heads/${GIT_TARGET_BRANCH}"

echo "[OK] local serve ${GIT_TARGET_BRANCH} is now $(git rev-parse --short HEAD)"