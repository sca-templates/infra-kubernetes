#!/usr/bin/env bash
# Copyright (c) 2026 sca-templates contributors
# SPDX-License-Identifier: MIT
# preload-chart-images.sh — warm the emulated-EKS k3s node with the container
# images the platform will run, so the smoke never depends on a public registry
# (and its per-IP throttling) at pod start.
#
# Why: on ephemeral CI runners a node-side pull can stall behind registry
# throttling well past a Deployment's progressDeadlineSeconds (one run burned
# 10 minutes on `Deployment/argocd-redis not ready: Progress deadline exceeded`
# because ecr-public.aws.com answered 429 to the runner's shared IP). Pulling
# through the host Docker — cached across runs in CI — and importing into the
# node's containerd takes the registry off the critical path.
#
# Two modes:
#   preload-chart-images.sh <chart> <repo-url> <version> [helm args...]
#       one chart (used by `make argocd-up` for argo-cd)
#   preload-chart-images.sh --catalog <env>
#       every platform Application for <env>: the `argocd/apps-<env>.yaml`
#       ApplicationSet elements plus the dedicated Applications
#       (`argocd/*-<env>.yaml`, e.g. kong), rendered with the same values files
#       ArgoCD uses (`infrastructure/<c>/values-base.yaml` + `envs/<env>/<c>.yaml`)
#
# Flow (both modes):
#   1. resolve the image refs from `helm template` (never drifts from manifests)
#   2. load the cached image tarball when present (actions/cache in CI)
#   3. pull the refs still missing with the host Docker — fail-closed, printing
#      the registry's own error
#   4. save a tarball for the next run (only when something was pulled)
#   5. import everything into the k3s node (docker save | k3s ctr images import)
#
# Env:
#   PRELOAD_CACHE_DIR  docker-save cache directory (default ~/.cache/sca/preload)
#   PRELOAD_LIST_ONLY  set to 1 to resolve and print the images, then exit
#   PRELOAD_SKIP       set to 1 to skip the preload entirely
#   K3S_CONTAINER      k3s node container (default: discovered with `docker ps`)
#   FLOCI_EKS_CLUSTER  emulated cluster name used for container discovery
#
# CI/dev tooling only — never a platform component (docs/ci-cd.md). Fail-closed
# on a pull/import error, so a throttled registry stops the run in seconds with
# an actionable message instead of a progressive-deadline timeout. With no k3s
# container (a real cluster) it is a no-op.
set -euo pipefail

# shellcheck source=bootstrap/versions.sh
. "$(dirname "$0")/versions.sh"

usage() {
  echo "usage: $0 <chart> <repo-url> <version> [helm args...]" >&2
  echo "       $0 [--list] --catalog <env>" >&2
  exit 2
}

echo_image_list() {
  local images="$1"
  printf '%s\n' "${images}" | sed '/^$/d'
}

warn() { printf '── preload: %s\n' "$*" >&2; }

# ── k3s node discovery ──────────────────────────────────────────────────────
# Floci runs one `rancher/k3s` container per cluster on the emulator's Docker
# network. Its name embeds the cluster name; the image is the reliable marker.
find_k3s_container() {
  if [ -n "${K3S_CONTAINER:-}" ]; then
    docker inspect "${K3S_CONTAINER}" >/dev/null 2>&1 && printf '%s' "${K3S_CONTAINER}"
    return 0
  fi
  docker ps --format '{{.Names}}	{{.Image}}' 2>/dev/null | awk -F'\t' -v c="${FLOCI_EKS_CLUSTER}" '
    index($2, "k3s") && index($1, c) { print $1; found = 1; exit }
    index($2, "k3s") && !fallback { fallback = $1 }
    END { if (!found && fallback) print fallback }'
}

# ── image resolution ────────────────────────────────────────────────────────
render_images() {
  # Print the unique image refs of one rendered chart. Refs without a tag or
  # digest are dropped: `docker pull repo` would resolve a different image.
  local rendered images img last
  rendered="$(helm template "$@")" || {
    echo "ERROR: helm template failed: $*" >&2
    return 1
  }
  images="$(printf '%s\n' "${rendered}" \
    | grep -oE 'image:[[:space:]]*[^[:space:]]+' \
    | sed -E 's/^image:[[:space:]]*//' \
    | tr -d '"' \
    | sort -u || true)"
  while IFS= read -r img; do
    [ -n "${img}" ] || continue
    last="${img##*/}"
    case "${last}" in
      *:* | *@sha256:*) printf '%s\n' "${img}" ;;
      *) warn "skipping '${img}' (no tag/digest in the rendered manifest)" ;;
    esac
  done <<< "${images}"
}

catalog_images() {
  local env="$1" apps_file="$2" f name ns repo chart version file images=""
  local raw_path include raw_file img last
  command -v npx >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || {
    echo "ERROR: --catalog needs node/npx (js-yaml) and jq" >&2
    return 1
  }
  [ -f "${apps_file}" ] || { echo "ERROR: ${apps_file} is missing" >&2; return 1; }

  # ApplicationSet elements rendered by the real app-of-apps.
  while IFS=$'\t' read -r name ns repo chart version; do
    [ -n "${name}" ] || continue
    local args=("${name}-preload" "${chart}" --repo "${repo}" --version "${version}" --namespace "${ns}")
    for file in "infrastructure/${name}/values-base.yaml" "envs/${env}/${name}.yaml"; do
      [ -f "${file}" ] && args+=(-f "${file}")
    done
    images+="$(render_images "${args[@]}")"$'\n'
  done < <(npx --yes js-yaml@4.1.0 "${apps_file}" \
    | jq -r '.spec.generators[] | select(.list) | .list.elements[]
             | [.name, .namespace, .chartRepo, .chart, .targetRevision] | @tsv')

  # Dedicated Applications (not part of the ApplicationSet), e.g. kong.
  while IFS= read -r f; do
    case "${f}" in
      */apps-* | */root-app-* | */services-* | *-smoke*) continue ;;
    esac
    while IFS=$'\t' read -r repo chart version; do
      [ -n "${chart}" ] || continue
      local args=("$(basename "${f}" .yaml)-preload" "${chart}" --repo "${repo}" --version "${version}")
      while IFS= read -r file; do
        file="${file#\$values/}"
        [ -f "${file}" ] && args+=(-f "${file}")
      done < <(npx --yes js-yaml@4.1.0 "${f}" | jq -r '.spec.sources[0].helm.valueFiles[]?')
      images+="$(render_images "${args[@]}")"$'\n'
    done < <(npx --yes js-yaml@4.1.0 "${f}" \
      | jq -r '.spec.sources[0] | select(.chart != null) | [.repoURL, .chart, .targetRevision] | @tsv')

    # Raw-manifest Applications (e.g. postgres-app): resolve the images their
    # included files pin, so datastore images are preloaded too. Chart sources
    # have no path and are skipped here.
    while IFS=$'\t' read -r raw_path include; do
      [ -n "${raw_path}" ] || continue
      if [ ! -d "${raw_path}" ]; then
        warn "raw source path '${raw_path}' from ${f} does not exist (skip)"
        continue
      fi
      while IFS= read -r raw_file; do
        while IFS= read -r img; do
          [ -n "${img}" ] || continue
          last="${img##*/}"
          case "${last}" in
            *:* | *@sha256:*) images+="${img}"$'\n' ;;
            *) warn "skipping '${img}' from ${raw_file} (no tag/digest)" ;;
          esac
        done < <(grep -hE '^[[:space:]]+image(Name)?:[[:space:]]*' "${raw_file}" \
          | sed -E 's/^[[:space:]]+image(Name)?:[[:space:]]*//' \
          | tr -d '"' | sort -u || true)
      done < <(if [ -n "${include}" ]; then
        find "${raw_path}" -maxdepth 1 -type f -name "${include}"
      else
        find "${raw_path}" -maxdepth 1 -type f -name '*.yaml'
      fi | sort)
    done < <(npx --yes js-yaml@4.1.0 "${f}" \
      | jq -r '((.spec.source // empty), ((.spec.sources // [])[]))
               | select(.path != null)
               | [.path, (.directory.include // "")] | @tsv')
  done < <(find argocd -maxdepth 1 -name "*-${env}.yaml" | sort)

  printf '%s\n' "${images}" | sed '/^$/d' | sort -u
}

# ── main ────────────────────────────────────────────────────────────────────
[ "${PRELOAD_SKIP:-0}" = "1" ] && { warn "PRELOAD_SKIP=1 (skip)"; exit 0; }

list_only="${PRELOAD_LIST_ONLY:-0}"
if [ "${1:-}" = "--list" ]; then
  list_only=1
  shift
fi

if [ "${1:-}" = "--catalog" ]; then
  mode=catalog
  shift
  catalog_env="${1:?usage: $0 --catalog <env>}"
  shift
  apps_file="argocd/apps-${catalog_env}.yaml"
else
  mode=chart
  [ "$#" -ge 3 ] || usage
  chart="$1"; repo="$2"; version="$3"; shift 3
fi

if ! command -v docker >/dev/null 2>&1; then
  warn "docker not found (skip; the node will pull images directly)"
  exit 0
fi

node=""
if [ "${list_only}" != "1" ]; then
  node="$(find_k3s_container)"
  if [ -z "${node}" ]; then
    warn "no k3s node container for '${FLOCI_EKS_CLUSTER}' (skip; the node will pull images directly)"
    exit 0
  fi
fi

command -v helm >/dev/null 2>&1 || { warn "helm not found (skip)"; exit 0; }

if [ "${mode}" = "catalog" ]; then
  echo "── preload: resolving images for ENV=${catalog_env} (argocd/apps-${catalog_env}.yaml + dedicated apps)"
  images="$(catalog_images "${catalog_env}" "${apps_file}")"
else
  echo "── preload: resolving images for ${chart}@${version}"
  images="$(render_images "${chart}-preload" "${chart}" --repo "${repo}" --version "${version}" "$@")"
fi

if [ -z "${images}" ]; then
  warn "no images resolved (skip)"
  exit 0
fi

if [ "${list_only}" = "1" ]; then
  echo_image_list "${images}"
  exit 0
fi

count="$(printf '%s\n' "${images}" | sed '/^$/d' | wc -l | tr -d ' ')"
echo "── preload: ${count} image(s) for node '${node}'"

# ── cache: docker image tarball from a previous run ─────────────────────────
CACHE_DIR="${PRELOAD_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/sca/preload}"
CACHE_TAR="${CACHE_DIR}/chart-images.tar"
if [ -f "${CACHE_TAR}" ]; then
  if docker load -i "${CACHE_TAR}" >/dev/null 2>&1; then
    echo "  cache: loaded ${CACHE_TAR}"
  else
    warn "cache: ${CACHE_TAR} is unreadable (ignoring)"
  fi
fi

# ── pull what is still missing (fail-closed) ────────────────────────────────
mapfile -t image_list < <(printf '%s\n' "${images}" | sed '/^$/d')
pulled=0
for image in "${image_list[@]}"; do
  if docker image inspect "${image}" >/dev/null 2>&1; then
    continue
  fi
  ok=0
  for attempt in 1 2 3; do
    if err="$(docker pull "${image}" 2>&1 >/dev/null)"; then
      ok=1
      break
    fi
    echo "  pull failed (attempt ${attempt}/3) for ${image}:" >&2
    printf '%s\n' "${err}" | tail -n 5 | sed 's/^/    /' >&2
    sleep $((attempt * 5))
  done
  [ "${ok}" = "1" ] || {
    echo "ERROR: could not pull ${image} — fix registry access (or warm PRELOAD_CACHE_DIR) instead of letting the node stall on it" >&2
    exit 1
  }
  echo "  pulled ${image}"
  pulled=1
done

# Refresh the cache tarball whenever we pulled something, or when it is missing
# (a layer-cached Docker still has the images, so we can still warm the cache).
if [ "${pulled}" = "1" ] || [ ! -f "${CACHE_TAR}" ]; then
  mkdir -p "${CACHE_DIR}"
  if docker save -o "${CACHE_TAR}.tmp" "${image_list[@]}" >/dev/null 2>&1; then
    mv "${CACHE_TAR}.tmp" "${CACHE_TAR}"
    echo "  cache: saved ${CACHE_TAR}"
  else
    rm -f "${CACHE_TAR}.tmp"
    warn "cache: could not save ${CACHE_TAR} (continuing)"
  fi
fi

# ── import into the k3s node's containerd ───────────────────────────────────
echo "── preload: importing into '${node}' (k3s ctr images import)"
if ! docker save "${image_list[@]}" | docker exec -i "${node}" k3s ctr images import - >/dev/null; then
  echo "ERROR: importing the preloaded images into '${node}' failed" >&2
  exit 1
fi
echo "── preload: done"
