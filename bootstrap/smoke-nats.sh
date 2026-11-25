#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# smoke-nats.sh — verify the NATS JetStream server is deployed and that
# JetStream is enabled and idle. NATS (ADR-005) is the event backbone; it ships
# "ready but idle" — the server runs with JetStream on
# and no `Stream`/`Consumer` CR in git, so the smoke proves JetStream answers
# and the default account holds zero streams. The chart's `nats-box` pod (the
# NATS CLI) is the tool used to query the server from inside the cluster.
# Selective smoke for the nats component; driven by
# `make smoke COMPONENT=nats` (see docs/ci-cd.md).
set -euo pipefail

NAMESPACE="${NATS_NS:-data}"
STATEFULSET="${NATS_STATEFULSET:-nats}"
BOX="${NATS_BOX:-nats-box}"
SERVER_URL="${NATS_URL:-nats://nats:4222}"
TIMEOUT="${SMOKE_TIMEOUT:-120s}"
APP="${NATS_APP:-nats-local}"

if ! kubectl get application "${APP}" -n argocd >/dev/null 2>&1; then
  echo "[SKIP] smoke(nats): Application ${APP} is not deployed (optional messaging tier)"
  exit 0
fi

echo "── smoke(nats): namespace ${NAMESPACE} present"
kubectl get namespace "$NAMESPACE" --no-headers >/dev/null

echo "── smoke(nats): statefulset ${NAMESPACE}/${STATEFULSET} Ready"
kubectl -n "$NAMESPACE" rollout status "statefulset/${STATEFULSET}" --timeout="$TIMEOUT" >/dev/null

echo "── smoke(nats): nats-box ${NAMESPACE}/${BOX} Ready"
kubectl -n "$NAMESPACE" rollout status "deployment/${BOX}" --timeout="$TIMEOUT" >/dev/null

# `nats stream ls` errors when JetStream is not enabled for the account, so a
# clean exit is the "JetStream is on" signal. Under the ready-but-idle contract
# the account holds no stream, so the CLI prints an empty/"No Streams defined"
# message and never a stream row.
echo "── smoke(nats): JetStream enabled and idle (0 streams)"
if ! streams_out="$(kubectl -n "$NAMESPACE" exec "deploy/${BOX}" -- \
      nats -s "$SERVER_URL" stream ls 2>&1)"; then
  echo "FAIL: 'nats stream ls' failed — JetStream may be disabled:" >&2
  printf '%s\n' "$streams_out" >&2
  exit 1
fi
if [ -n "$streams_out" ] && ! printf '%s' "$streams_out" | grep -qiE 'no streams|no results|not defined'; then
  echo "FAIL: expected zero streams (ready-but-idle), got:" >&2
  printf '%s\n' "$streams_out" >&2
  exit 1
fi
echo "  JetStream enabled, 0 streams"

echo "[OK] smoke(nats): statefulset Ready, JetStream enabled, 0 streams (idle)"
