#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# local-git-down.sh — stop the local git serve pod (keeps the bare mirror on
# host and node).
# Usage: make local-git-down
set -euo pipefail

kubectl delete pod git-local-serve --namespace git-serve --ignore-not-found >/dev/null 2>&1
kubectl delete namespace git-serve --ignore-not-found >/dev/null 2>&1
echo "[OK] local git serve stopped (host mirror kept at .git-local/sca-infra.git)"