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
#   2. inventory the k3s node's containerd and exit early when nothing is missing
#   3. load the cached image tarball when the host still lacks a missing ref
#      (actions/cache in CI), then pull the rest — fail-closed, printing the
#      registry's own error
#   4. save a tarball for the next run when free space allows (only when
#      something was pulled or the cache is missing/unreadable)
#   5. import only the missing refs into the node (docker save | ctr images import)
#      with a heartbeat and a hard timeout. The import is pinned to the host
#      platform: Docker's OCI archive can reference attestation manifests it
#      does not include, and an unfiltered import fails with
#      "content digest ...: not found" (containerd#11344)
#   6. drop the host-side copy: the node owns its own in containerd, and the
#      runner's ephemeral storage must not hold the catalog twice
#
# Env:
#   PRELOAD_CACHE_DIR      docker-save cache directory (default ~/.cache/sca/preload)
#   PRELOAD_CACHE_FILE     explicit cache tarball (default <mode>-<name>-images.tar)
#   PRELOAD_MIN_FREE_GIB   skip saving the cache tarball below this many GiB (default 10)
#   PRELOAD_PLATFORM       platform imported into containerd (default: host arch)
#   PRELOAD_SAVE_TIMEOUT   seconds allowed for `docker save` (default 600)
#   PRELOAD_IMPORT_TIMEOUT seconds allowed for `ctr images import` (default 900)
#   PRELOAD_LIST_ONLY      set to 1 to resolve and print the images, then exit
#   PRELOAD_SKIP           set to 1 to skip the preload entirely
#   K3S_CONTAINER          k3s node container (default: discovered with `docker ps`)
#   FLOCI_EKS_CLUSTER      emulated cluster name used for container discovery
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

# Normalize a Docker ref to the name containerd stores (`docker.io/...`), so a
# ref rendered as `redis:tag` matches `docker.io/library/redis:tag` on the node.
normalize_image_ref() {
  local ref="$1" first rest
  case "$ref" in
    *@sha256:*) printf '%s\n' "$ref"; return 0 ;;
  esac
  case "$ref" in
    docker.io/*) rest="${ref#docker.io/}" ;;
    index.docker.io/*) rest="${ref#index.docker.io/}" ;;
    */*)
      first="${ref%%/*}"
      case "$first" in
        *.* | *:* | localhost) printf '%s\n' "$ref"; return 0 ;;
        *) rest="$ref" ;;
      esac ;;
    *) rest="$ref" ;;
  esac
  case "$rest" in
    */*) printf 'docker.io/%s\n' "$rest" ;;
    *) printf 'docker.io/library/%s\n' "$rest" ;;
  esac
}

# node_images is populated once from `ctr images ls -q`; compare both the raw
# ref and its normalized form, and match digests by their digest suffix.
node_has_image() {
  local ref="$1" cand digest
  case "$ref" in
    *@sha256:*)
      digest="${ref##*@}"
      printf '%s\n' "${node_images}" | grep -Fq "@${digest}" && return 0 ;;
  esac
  cand="$(normalize_image_ref "$ref")"
  printf '%s\n' "${node_images}" | grep -Fxq "${cand}" && return 0
  printf '%s\n' "${node_images}" | grep -Fxq "${ref}" && return 0
  return 1
}

# GNU timeout is not installed on macOS by default; keep the heartbeat and just
# run the command unbounded there. Linux/CI get the hard ceiling.
with_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "${secs}" "$@"
  else
    "$@"
  fi
}

# GiB available on the filesystem that holds a path (0 when df cannot read it).
free_gib() {
  df -Pk "$1" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024/1024}'
}

# ── k3s node discovery ──────────────────────────────────────────────────────
# Floci runs one node container per cluster on the emulator's Docker network.
# Its name embeds the cluster (`floci-aws-eks-<cluster>`), while the image can
# be a pinned digest without "k3s" in the reference; match the name first and
# the image second so CI and local discovery agree.
find_k3s_container() {
  if [ -n "${K3S_CONTAINER:-}" ]; then
    docker inspect "${K3S_CONTAINER}" >/dev/null 2>&1 && printf '%s' "${K3S_CONTAINER}"
    return 0
  fi
  docker ps --format '{{.Names}}	{{.Image}}' 2>/dev/null | awk -F'\t' -v c="${FLOCI_EKS_CLUSTER}" '
    c != "" && index($1, c) { print $1; found = 1; exit }
    index($1, "floci-aws-eks-") && !by_name { by_name = $1 }
    index($2, "k3s") && !by_image { by_image = $1 }
    END {
      if (found) exit
      if (by_name) print by_name
      else if (by_image) print by_image
    }'
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

# ── node inventory: skip the whole preload when the node already has them ───
# Re-importing 4.5 GiB on every run was the local 30-minute stall; the node is
# the authority on what it needs, so check it before touching the host cache.
ctr_cmd=(/bin/ctr --address /run/k3s/containerd/containerd.sock --namespace k8s.io)
if ! docker exec "${node}" "${ctr_cmd[@]}" version >/dev/null; then
  echo "ERROR: ctr is not usable inside node '${node}' (containerd socket not ready?)" >&2
  exit 1
fi
node_images="$(docker exec "${node}" "${ctr_cmd[@]}" images ls -q 2>/dev/null)" || {
  echo "ERROR: cannot list images inside node '${node}'" >&2
  exit 1
}
mapfile -t image_list < <(printf '%s\n' "${images}" | sed '/^$/d')
missing=()
for image in "${image_list[@]}"; do
  node_has_image "${image}" || missing+=("${image}")
done
if [ "${#missing[@]}" -eq 0 ]; then
  echo "  all ${count} image(s) already present in '${node}' (skip import)"
  echo "── preload: done"
  exit 0
fi
echo "  ${#missing[@]}/${count} image(s) missing from '${node}'"

# ── cache: docker image tarball from a previous run ─────────────────────────
# One tarball per mode/name: `argocd-up` (chart) and `bootstrap` (catalog) run
# back-to-back against the same node, and a shared tarball let the 2-image
# ArgoCD preload replace the 25-image catalog cache before bootstrap loaded it.
CACHE_DIR="${PRELOAD_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/sca/preload}"
if [ "${mode}" = "catalog" ]; then
  cache_name="catalog-${catalog_env}-images.tar"
else
  cache_name="chart-${chart}-images.tar"
fi
cache_name="$(printf '%s' "${cache_name}" | tr '/:' '__')"
CACHE_TAR="${PRELOAD_CACHE_FILE:-${CACHE_DIR}/${cache_name}}"
cache_valid=0
if [ -f "${CACHE_TAR}" ]; then
  need_load=0
  for image in "${missing[@]}"; do
    docker image inspect "${image}" >/dev/null 2>&1 || { need_load=1; break; }
  done
  if [ "${need_load}" = "0" ]; then
    echo "  cache: missing images already in host Docker (skip load)"
    cache_valid=1
  elif docker load -i "${CACHE_TAR}" >/dev/null 2>&1; then
    echo "  cache: loaded ${CACHE_TAR}"
    # Keep the tarball: actions/cache restores it next run, and deleting it here
    # made every run re-save 4.5 GiB even when nothing was pulled.
    cache_valid=1
  else
    warn "cache: ${CACHE_TAR} is unreadable (ignoring)"
  fi
fi

# ── pull what is still missing (fail-closed) ────────────────────────────────
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

# Refresh the cache tarball only when something was pulled or the cache was
# missing/unreadable (a layer-cached Docker still has the images, so we can
# still warm the cache). A valid cache is kept as-is.
if [ "${pulled}" = "1" ] || [ "${cache_valid}" = "0" ]; then
  cache_dir="$(dirname "${CACHE_TAR}")"
  mkdir -p "${cache_dir}"
  free_now="$(free_gib "${cache_dir}")"
  free_now="${free_now:-0}"
  min_free="${PRELOAD_MIN_FREE_GIB:-10}"
  if [ "${free_now}" -lt "${min_free}" ]; then
    warn "cache: only ${free_now} GiB free on ${cache_dir}; not saving ${CACHE_TAR} (the node keeps the images)"
  elif docker save -o "${CACHE_TAR}.tmp" "${image_list[@]}" >/dev/null 2>&1; then
    mv "${CACHE_TAR}.tmp" "${CACHE_TAR}"
    echo "  cache: saved ${CACHE_TAR}"
  else
    rm -f "${CACHE_TAR}.tmp"
    warn "cache: could not save ${CACHE_TAR} (continuing)"
  fi
fi

# ── import the missing images into the k3s node's containerd ────────────────
# Stream only the missing refs and keep a heartbeat: the previous all-images
# pipeline wrote no output for the whole import, which looked like a hang.
# `--platform` keeps containerd from chasing attestation or foreign-platform
# manifests that `docker save` did not include (containerd#11344). Do not use
# `docker save --platform`: it drops or unnames digest-pinned refs.
node_arch="$(docker version --format '{{.Server.Arch}}' 2>/dev/null || true)"
[ -n "${node_arch}" ] && [ "${node_arch}" != "<no value>" ] || node_arch="$(uname -m)"
case "${node_arch}" in
  amd64 | x86_64) node_platform=linux/amd64 ;;
  arm64 | aarch64) node_platform=linux/arm64 ;;
  *) node_platform="linux/${node_arch}" ;;
esac
node_platform="${PRELOAD_PLATFORM:-${node_platform}}"
echo "── preload: importing ${#missing[@]} image(s) into '${node}' for ${node_platform} (ctr images import)"
save_timeout="${PRELOAD_SAVE_TIMEOUT:-600}"
import_timeout="${PRELOAD_IMPORT_TIMEOUT:-900}"
(
  set -o pipefail
  with_timeout "${save_timeout}" docker save "${missing[@]}" \
    | with_timeout "${import_timeout}" docker exec -i "${node}" "${ctr_cmd[@]}" images import --platform "${node_platform}" -
) &
import_pid=$!
elapsed=0
while kill -0 "${import_pid}" 2>/dev/null; do
  sleep 15
  if kill -0 "${import_pid}" 2>/dev/null; then
    elapsed=$((elapsed + 15))
    echo "  ... import still running (${elapsed}s)" >&2
  fi
done
import_status=0
wait "${import_pid}" || import_status=$?
if [ "${import_status}" -ne 0 ]; then
  case "${import_status}" in
    124) echo "ERROR: importing the preloaded images timed out after ${import_timeout}s" >&2 ;;
    *) echo "ERROR: importing the preloaded images into '${node}' failed (status ${import_status})" >&2 ;;
  esac
  exit 1
fi
# The node now owns its copy in containerd; drop the host-side copy so the
# runner's ephemeral storage does not hold the catalog twice.
docker rmi "${image_list[@]}" >/dev/null 2>&1 || true
echo "── preload: done"
