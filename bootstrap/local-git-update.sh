#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# local-git-update.sh — mirror the working tree into the local git serve so the
# local ArgoCD picks it up without pushing to GitHub. After every local commit:
#   make local-git-update
# Usage: make local-git-update [GIT_TARGET_BRANCH=<branch>]
set -euo pipefail

GIT_TARGET_BRANCH="${GIT_TARGET_BRANCH:-main}"
BARE=".git-local/sca-infra.git"

[ -d "${BARE}/objects" ] || { echo 'ERROR: no local bare repo — run make local-git-up first'; exit 1; }

echo "── mirroring HEAD → refs/heads/${GIT_TARGET_BRANCH} (local serve)"
git push --force "${BARE}" "HEAD:refs/heads/${GIT_TARGET_BRANCH}"

echo "[OK] local serve ${GIT_TARGET_BRANCH} is now $(git --git-dir="${BARE}" rev-parse --short "${GIT_TARGET_BRANCH}")"