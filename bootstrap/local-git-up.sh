#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# local-git-up.sh — stand up the fully-local git serve for the local kind
# platform: a bare mirror of this repo served read-only over git://, plus the
# .env seam pointing GIT_REPO_URL at it. Local ArgoCD then reconciles local
# content with zero dependency on GitHub; `make local-git-update` pushes the
# working tree into the serve. See docs/ci-cd.md and .env.example.
# Usage: make local-git-up
set -euo pipefail

GIT_TARGET_BRANCH="${GIT_TARGET_BRANCH:-main}"
BASE_DIR=".git-local"
BARE="${BASE_DIR}/sca-infra.git"
PID_FILE="${BASE_DIR}/git-daemon.pid"
LOG_FILE="${BASE_DIR}/git-daemon.log"
PORT="${GIT_DAEMON_PORT:-9418}"

mkdir -p "$BASE_DIR"

if [ -d "${BARE}/objects" ]; then
  echo "[skip] local bare repo already exists: ${BARE}"
else
  echo "── creating local bare mirror of the working repo: ${BARE}"
  git clone --bare . "${BARE}" >/dev/null
fi
git --git-dir="${BARE}" rev-parse --is-bare-repository >/dev/null

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "[skip] git daemon already running (pid $(cat "$PID_FILE"), port ${PORT})"
else
  echo "── starting git daemon on port ${PORT} (read-only, local serve)"
  nohup git daemon \
    --base-path="$BASE_DIR" --export-all --reuseaddr \
    --port="$PORT" --pid-file="$PID_FILE" \
    >"$LOG_FILE" 2>&1 &
  sleep 1
  kill -0 "$(cat "$PID_FILE")" 2>/dev/null || { echo "ERROR: git daemon failed to start — see ${LOG_FILE}"; exit 1; }
fi

gateway="$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || true)"
case "$gateway" in
  *"."*) ;;
  *) echo "ERROR: cannot detect the kind network gateway (is the cluster up?)"; exit 1 ;;
esac
serve_url="git://${gateway}:${PORT}/sca-infra.git"

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