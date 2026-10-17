#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# preload-chart-images.sh — render a chart, pull its container images with the
# host Docker and load them into the local kind node, so an ephemeral cluster
# never depends on the node pulling from a public registry at runtime.
#
# Why: on ephemeral CI runners a node-side pull can stall behind registry
# throttling well past a Deployment's progressDeadlineSeconds, surfacing as a
# flaky `argocd-up` failure (Deployment/argocd-redis not ready: Progress
# deadline exceeded) that no Helm --timeout can fix. Pre-pulling through the
# host and loading via `kind load` removes the registry from the critical path.
#
# CI/dev tooling only — never a platform component (docs/ci-cd.md). Fail-soft:
# a pull/load error never fails the caller; the node just pulls on its own as
# before. On any substrate but `kind` (e.g. the EKS/k3s substrate, which pulls
# directly and has not flaked) it is a no-op.
#
# Usage:
#   preload-chart-images.sh <chart> <repo-url> <version> [helm args...]
#
# Env:
#   KIND_CLUSTER_NAME  kind cluster to load into (default: sca-local)
set -euo pipefail

chart="${1:?usage: $0 <chart> <repo-url> <version> [helm args...]}"
repo="${2:?usage: $0 <chart> <repo-url> <version> [helm args...]}"
version="${3:?usage: $0 <chart> <repo-url> <version> [helm args...]}"
shift 3

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-sca-local}"
node="${KIND_CLUSTER_NAME}-control-plane"

# Only the kind substrate has a node Docker container we can load into.
if ! command -v docker >/dev/null 2>&1 || ! docker inspect "${node}" >/dev/null 2>&1; then
  echo "── preload: no kind node '${node}' (skip; the node will pull images directly)"
  exit 0
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "── preload: helm not found (skip)"
  exit 0
fi

# Discover the images the chart will actually deploy, so the preload never drifts
# from the rendered manifests.
images="$(helm template "${chart}-preload" "${chart}" --repo "${repo}" --version "${version}" "$@" \
  | grep -oE 'image:[[:space:]]*[^[:space:]]+' \
  | sed -E 's/^image:[[:space:]]*//' \
  | tr -d '"' \
  | sort -u || true)"

if [ -z "${images}" ]; then
  echo "── preload: no images resolved from ${chart}@${version} (skip)"
  exit 0
fi

echo "── preload: pulling chart images with the host Docker (registry throttling avoided)"
while IFS= read -r image; do
  [ -n "${image}" ] || continue
  pulled=0
  for attempt in 1 2 3; do
    if docker pull "${image}" >/dev/null 2>&1; then
      pulled=1
      break
    fi
    echo "── preload: pull failed (attempt ${attempt}/3) for ${image}; retrying"
    sleep $((attempt * 5))
  done
  if [ "${pulled}" = "1" ]; then
    echo "── preload:   pulled ${image}"
  else
    echo "── preload:   WARN could not pull ${image}; the node will pull it directly"
  fi
done <<< "${images}"

# Load whatever made it into the host Docker into the kind node; the chart's
# default imagePullPolicy is IfNotPresent, so the loaded image is used as-is.
loaded=()
while IFS= read -r image; do
  [ -n "${image}" ] || continue
  docker image inspect "${image}" >/dev/null 2>&1 && loaded+=("${image}") || true
done <<< "${images}"

if [ "${#loaded[@]}" -eq 0 ]; then
  echo "── preload: nothing to load (skip)"
  exit 0
fi

echo "── preload: loading ${#loaded[@]} image(s) into '${node}'"
if kind load docker-image "${loaded[@]}" --name "${KIND_CLUSTER_NAME}" >/dev/null 2>&1; then
  echo "── preload: done"
else
  echo "── preload: WARN kind load failed; the node will pull images directly"
fi
