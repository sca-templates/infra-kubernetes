#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# local-git-down.sh — stop the local git serve (keeps the bare mirror).
# Usage: make local-git-down
set -euo pipefail

BASE_DIR=".git-local"
PID_FILE="${BASE_DIR}/git-daemon.pid"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  kill "$(cat "$PID_FILE")" >/dev/null 2>&1 || true
  rm -f "$PID_FILE"
  echo "[OK] git daemon stopped"
else
  rm -f "$PID_FILE"
  echo "[skip] no git daemon running"
fi