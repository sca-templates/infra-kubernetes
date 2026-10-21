# Roadmap — Delivery Plan

Context: `infra-kubernetes`, the GitOps source of truth for the `sca` platform
on Kubernetes. Board: [Kubernetes Planning](https://github.com/orgs/sca-templates/projects/1) (org Project) · Milestones: one per project below · Issues: linked per project.

This file is the index for the delivery plan. Per-project detail lives in
`docs/roadmap/<project>.md`; what is deployed *now* lives in
[status.md](status.md); the component catalog and sync-waves live in
[architecture.md](architecture.md). Tracking happens on the **Kubernetes
Planning** board: one epic issue per component (sub-issues for out-phased
components), grouped by `Domain` and `Wave`.

## Timeline (dependency graph)

Dependencies flow forward (child waits for parent); layers with no link can be
worked in parallel.

```text
[01 cert-manager] ──▶ [02 vault] ──▶ [03 external-secrets]
[04 linkerd-crds] ──────────────────────────────▶ [09 linkerd control plane]
[05 cloudnative-pg] ──▶ [10 postgres-app]
[06 strimzi] ─────────▶ [11 kafka]
[07 redis-operator] ──▶ [12 redis]
[08 kong]
[13 keycloak]
[14 kube-prometheus-stack] ──┬─▶ [15 loki/alloy]
                             └─▶ [16 tempo]
[17 minio] ──▶ [18 velero]
```

- **Wave −20/−10**: security + operator layer — `01`–`07` install first,
  largely in parallel (each is an operator/CRD).
- **Wave 0/20/30**: `02` Vault, `08` Kong, `09` linkerd control plane —
  sequential behind their dependencies.
- **Wave 40**: datastores `10`–`12` (clusters/CRs) behind their operators.
- **Wave 50**: `13` Keycloak behind its DB (`10`).
- **Wave 60**: observability `14`–`16` (parallel after data keys).
- **Wave 70/80**: `17` MinIO (local only) then `18` Velero.
- Everything is **local-first**; promotion to `dev`/`qa`/`prod` is gated per
  green project (see [workflow.md](workflow.md)).

## Definition of Done (applies to every project)

- Application `Synced` + `Healthy` in ArgoCD.
- Pods `Running`, no `CrashLoopBackOff` / `ImagePullBackOff` after 2+ min stable.
- `ExternalSecret` → `SecretSynced` where applicable.
- One functional smoke (per-project gate, in each project file).
- `make status` shows no new `Degraded`.
- Single commit, human-reviewed; docs updated in the same commit (this file's
  Work Log + `architecture.md` + `status.md`).

> **CI note (does not change with this roadmap):** the Validate workflow runs
> `kube-linter` over any `infrastructure/*/manifests/*.yaml` it finds. As each
> component lands a `manifests/` directory in Phase 1+, kube-linter covers it
> automatically — no per-component wiring is needed.
>
> **CI note (cluster smoke):** the cluster smoke (`pr-cluster.yml`) is a
> Phase 1 deliverable that landed with cert-manager and runs
> automatically for every subsequent component — each project's "one
> functional smoke" (in the per-project gate above) becomes the `pr-cluster`
> smoke command. No per-component workflow wiring is needed beyond the
> component's smoke command in `bootstrap/smoke-target.sh`. It smokes the
> touched component on PRs as the required `Smoke` check on `main`
> (branch protection), with a manual `workflow_dispatch` for one-off
> testing; there is no `push`-triggered smoke. Profile: `local` (see
> [ci-cd.md](ci-cd.md)).

## Projects (index)

| Project | Area | Wave | Milestones | Issues | Status |
| --- | --- | --- | --- | --- | --- |
| [cert-manager](roadmap/cert-manager.md) | Security & Identity | -20 | — | [#6](https://github.com/sca-templates/infra-kubernetes/issues/6) | deployed |
| [vault](roadmap/vault.md) | Security & Identity | 0 | M1 bootstrap · M2 seed · M2 integration | [#7](https://github.com/sca-templates/infra-kubernetes/issues/7) · [#24](https://github.com/sca-templates/infra-kubernetes/issues/24) · [#25](https://github.com/sca-templates/infra-kubernetes/issues/25) · [#26](https://github.com/sca-templates/infra-kubernetes/issues/26) | deployed |
| [external-secrets](roadmap/external-secrets.md) | Security & Identity | -10 | — | [#8](https://github.com/sca-templates/infra-kubernetes/issues/8) | deployed |
| [linkerd-crds](roadmap/linkerd-crds.md) | Edge & Mesh | -10 | — | [#9](https://github.com/sca-templates/infra-kubernetes/issues/9) | deployed |
| [cloudnative-pg](roadmap/cloudnative-pg.md) | Data | -10 | — | [#10](https://github.com/sca-templates/infra-kubernetes/issues/10) | deployed |
| [strimzi](roadmap/strimzi.md) | Data | -10 | — | [#11](https://github.com/sca-templates/infra-kubernetes/issues/11) | deployed |
| [redis-operator](roadmap/redis-operator.md) | Data | -10 | — | [#12](https://github.com/sca-templates/infra-kubernetes/issues/12) | deployed |
| [kong](roadmap/kong.md) | Edge & Mesh | 20 | M1 dedicated app | [#13](https://github.com/sca-templates/infra-kubernetes/issues/13) | deployed |
| [linkerd](roadmap/linkerd.md) | Edge & Mesh | 30 | M1 control plane | [#14](https://github.com/sca-templates/infra-kubernetes/issues/14) | deployed |
| [postgres-app](roadmap/postgres-app.md) | Data | 40 | M1 cluster · M1 keycloak-db | [#15](https://github.com/sca-templates/infra-kubernetes/issues/15) · [#27](https://github.com/sca-templates/infra-kubernetes/issues/27) · [#28](https://github.com/sca-templates/infra-kubernetes/issues/28) | pending |
| [kafka](roadmap/kafka.md) | Data | 40 | M1 CR + SCRAM | [#16](https://github.com/sca-templates/infra-kubernetes/issues/16) | pending |
| [redis](roadmap/redis.md) | Data | 40 | — | [#17](https://github.com/sca-templates/infra-kubernetes/issues/17) | pending |
| [keycloak](roadmap/keycloak.md) | Security & Identity | 50 | M1 deploy | [#18](https://github.com/sca-templates/infra-kubernetes/issues/18) | pending |
| [kube-prometheus-stack](roadmap/kube-prometheus-stack.md) | Observability | 60 | M1 stack · M2 radar | [#19](https://github.com/sca-templates/infra-kubernetes/issues/19) · [#29](https://github.com/sca-templates/infra-kubernetes/issues/29) | pending |
| [loki](roadmap/loki.md) | Observability | 60 | M1 loki · M2 alloy | [#20](https://github.com/sca-templates/infra-kubernetes/issues/20) | pending |
| [tempo](roadmap/tempo.md) | Observability | 60 | — | [#21](https://github.com/sca-templates/infra-kubernetes/issues/21) | pending |
| [minio](roadmap/minio.md) | Delivery & Resilience | 70 | — | [#22](https://github.com/sca-templates/infra-kubernetes/issues/22) | pending |
| [velero](roadmap/velero.md) | Delivery & Resilience | 80 | M1 install · M2 restore | [#23](https://github.com/sca-templates/infra-kubernetes/issues/23) · [#30](https://github.com/sca-templates/infra-kubernetes/issues/30) | pending |

Issues are the tracker; `#N` links resolve to `infra-kubernetes`. Sub-issues
(collections under an epic) match the out-phased components (Vault, postgres-app,
kube-prometheus-stack, Velero). Status remains `pending` until the component
lands (see the Work Log below).

## Work log (global, reverse-chronological)

| Date | Project | Gate | Commit | Issue |
| --- | --- | --- | --- | --- |
| 2026-10-20 | linkerd | deployed — chart `linkerd/linkerd-control-plane` 1.16.11 (`stable-2.14.10`) from `https://helm.linkerd.io/stable` as a **dedicated `Application` per env** (`linkerd-<env>`) in ns `linkerd`, app wave 30 across all 4 envs (deviation from the planned `linkerd install` script: the CI cluster smoke requires every catalog entry to be an ArgoCD `Application` that converges — same shape as Kong). Identity PKI provided **in-cluster** (`identity.externalCA=true` + `identity.issuer.scheme=kubernetes.io/tls`): the mesh root CA is committed as a `Secret` (`linkerd-identity-anchor`) consumed by a `type: CA` `Issuer`, cert-manager issues the issuer `Secret` (`linkerd-identity-issuer`), and the public anchor lands in the `linkerd-identity-trust-roots` `ConfigMap`; the chart-generated webhook certs are handled with `ignoreDifferences` (Secrets + webhook `caBundle`s). No `linkerd-viz` (headless mesh; golden signals scraped by Phase 14). `cniEnabled: false` (ephemeral `proxy-init`), heartbeat off, `podMonitor` off (CRDs arrive Phase 14), 1 replica (local/dev) / 3 + PDB + anti-affinity (qa/prod); smoke = control-plane Deployments Ready + identity chain (`openssl verify` anchor→issuer) + 3 webhooks wired (`make smoke COMPONENT=linkerd`) | `feat/phase-9` (PR) | [#14](https://github.com/sca-templates/infra-kubernetes/issues/14) |
| 2026-10-20 | beartype in the checkov lockfile (CI) | `beartype==0.22.9` (transitive: `checkov → spdx-tools → beartype`) does `from typing import no_type_check_decorator` in `beartype/typing/__init__.py`, a symbol CPython removed in 3.15, so the `Security` IaC gate died at import — `ImportError: cannot import name 'no_type_check_decorator'` — on runner images whose toolcache advertises Python 3.15 for the template's `python-version: "3.x"` (intermittent: earlier runs got 3.14). Fixed by `.github/beartype-override.txt` (`beartype==0.23.1`, which drops the import; `spdx-tools` sets no upper bound on beartype) consumed with `--overrides` **without** `--upgrade-package`, so the diff is the single `beartype` entry — naming the package would re-resolve the whole closure and drag ~20 unrelated packages (gitpython, multidict, pydantic, ...). The cutoff moves to `2026-10-12T00:00:00Z` to admit `0.23.1` (shipped 2026-10-11). The **root cause** — the lockfile is `--python-version 3.11` while the template installs `python-version: "3.x"` — is owed to `CI-CD-Templates` and documented in [security.md](security.md) | `feat/floci` (PR) | — |
| 2026-10-20 | aiohttp in the checkov lockfile (CI) | three advisories against `aiohttp==3.14.3` (GHSA-2g87-pp6c-29x5, GHSA-494j-54xm-rwp3, GHSA-5wr8-gcqf-gqf3, all fixed in `3.14.4`) failed the `Security` gate. `3.14.4` shipped 2026-10-05, after the lockfile's `--exclude-newer 2026-09-22T00:00:00Z` cutoff, so the cutoff moves to `2026-10-06T00:00:00Z` and the package is named with `--upgrade-package aiohttp`. The bump drags `yarl` (`1.24.5` → `1.25.1`), **not** collateral: `aiohttp==3.14.4` declares `yarl<2.0,>=1.25.1`, so the two-package diff is the fix's own closure; `yarl==1.25.1` shipped 2026-09-15, inside the old cutoff, and was surviving purely as a `uv pip compile` preference. Same package set, `checkov` stays `3.3.16`, its IaC baseline untouched, and no `IgnoredVulns` added (the only remaining advisory is the documented `ecdsa` one). Replaces the Dependabot pip security PR that rewrote the whole hash-pinned closure (the `pip` watch stays absent on purpose, see [security.md](security.md)) | `feat/floci` (PR) | — |
| 2026-10-20 | retire kind (Floci EKS single substrate) | `kind` retired repo-wide as the local/CI cluster substrate: Floci's emulated EKS (`make eks-up` / `make eks-status` / `make eks-down`, `bootstrap/eks-emulator.sh` — a real single-node k3s node + ECR) is now the **only** substrate for local dev and the CI cluster smoke. The Makefile's `cluster-up`/`cluster-down` targets and `bootstrap/kind-config.yaml` are deleted; `bootstrap/sca.sh prereqs` installs only kubectl+helm (docker required for the emulator); `bootstrap/smoke-ci.sh` has a single path — boot the full platform on the EKS substrate, seed Vault **before** the `Synced`/`Healthy` health gate, then run the component + EKS/ECR + cloud smokes; `pr-cluster.yml` collapses to the one `cluster-smoke`/`Smoke` job with image caching. The kind images preload is replaced by a **catalog-wide** preload (`bootstrap/preload-chart-images.sh --catalog <env>`) with a docker-image tarball cache at `~/.cache/sca/preload` (`PRELOAD_CACHE_DIR`). Vault is now seeded before the health gate; the redis image is pinned to `docker.io/library/redis` to dodge the ecr-public 429 (see [ci-cd.md](ci-cd.md)) |  |  |
| 2026-10-17 | argocd-up image pre-pull + diagnostics (CI) | `make argocd-up` now pre-pulls the chart's images with the host Docker and loads them into the kind node (`bootstrap/preload-chart-images.sh`) before Helm runs — a node-side pull on an ephemeral runner can stall behind registry throttling past a Deployment's `progressDeadlineSeconds`, surfacing as a flaky `argocd-up` failure (`Deployment/argocd-redis not ready: Progress deadline exceeded`) that no Helm `--timeout` can fix. The mechanism was confirmed by rendering chart `9.5.22` (images `quay.io/argoproj/argocd:v3.4.4` + `ecr-public.aws.com/docker/library/redis:8.2.3-alpine`); the preload is a no-op on the EKS/k3s substrate (pulls directly, has not flaked). If `argocd-up` still fails, `bootstrap/collect-argocd-diagnostics.sh` dumps the ArgoCD install state (pods/describe/events) into `.generated/`, because the framework's `diagnose` runs only *after* ArgoCD is up. Also raised the ArgoCD Helm wait to 15m and `SMOKE_TIMEOUT` to 1200s (see [ci-cd.md](ci-cd.md)) | `feat/floci` (PR) | — |
| 2026-10-17 | EKS emulator create retry-safety (CI) | `aws eks create-cluster` is now issued **once** (the AWS CLI's own retries are off via `AWS_MAX_ATTEMPTS=1`): Floci's `create` is not idempotent while it provisions k3s, so a retried request provisions a **second** k3s container — reproduced directly (one client call → two `Starting k3s container for EKS cluster` lines, the first container later dropped as stale), and the cause of CI's `ResourceInUseException: Cluster already exists`. `cluster_status` now distinguishes `ACTIVE`/`ABSENT` (404)/`UNKNOWN` instead of swallowing every error, so only a definite 404 triggers `create`; the old `wait_for_edge` (TCP, which docker-proxy accepts immediately) is replaced by `wait_for_api` (`eks list-clusters`); a tolerated `create` error no longer fails the run — the script converges via `wait_for_cluster_active` (ACTIVE ok, FAILED fatal). Also fixed `make eks-status`, which hit `Unauthorized` because it did not source `.secrets/eks-admin.env` the way `smoke-eks.sh` does (see [ci-cd.md](ci-cd.md)) | `5bee605` (PR) | — |
| 2026-10-15 | EKS substrate (CI) | `bootstrap/eks-emulator.sh` (`make eks-up` / `make eks-down` / `make eks-status`) drives Floci in **EKS mode** on a dedicated Docker network: mints a throwaway IAM user/key (`.secrets/eks-admin.env`, reused on re-run), `aws eks create-cluster` backed by a real single-node **k3s** container plus an OCI **ECR** registry, writes the stable `floci-eks` kube-context and waits for the node `Ready`. The required `Smoke` job then boots the **full platform** on it by applying the real `make bootstrap` app-of-apps — every `<name>-local` Application to `Synced`/`Healthy` — proving the two EKS-only paths kind cannot: an IAM-authenticated kubeconfig to a live API server and an in-cluster image pull from the emulated ECR (`bootstrap/smoke-eks.sh` → `EKS_ECR_PULL_OK`). Dev/CI tooling, not a catalog component (see [ci-cd.md](ci-cd.md)) | `feat/floci` (PR) | — |
| 2026-10-15 | Multi-component cluster smoke (CI) | `pr-cluster.yml` resolves the set of components a PR touches and smokes **all of them in one run** (single boot → cloud → EKS → teardown) instead of one component per run; changes to the smoke framework resolve to `cert-manager` so the machinery is self-validated (see [ci-cd.md](ci-cd.md)) | `feat/floci` (PR) | — |
| 2026-10-15 | Cloud emulator (CI) | the cluster smoke stands up a local cloud emulator (**Floci**, `bootstrap/cloud-emulator.sh`, `make cloud-up` / `make cloud-down` / `make cloud-status`) as a Docker container published into the cluster via a selector-less `Service` + `EndpointSlice` in a scratch `cloud` namespace; every smoke run proves the cluster reaches it (`make smoke COMPONENT=cloud` — bucket created and object round-tripped from an in-cluster Job), on by default with `--no-cloud` / `SMOKE_CLOUD=0` opt-out. Dev/CI tooling, not a catalog component (see [ci-cd.md](ci-cd.md), [architecture.md](architecture.md)) | `cd66fb3` (squash of PR #90) | — |
| 2026-10-13 | kong | deployed — chart `kong/kong` 3.4.1 from `https://charts.konghq.com` (gateway `kong:3.9.4`, bundled Ingress Controller `kong/kubernetes-ingress-controller:3.5.5`) as a **dedicated `Application` per env** (`kong-<env>`) in ns `kong`, **no `ServerSideApply`** (the appset's SSA breaks Kong's flat-schema `configuration.konghq.com` CRDs), app wave 20 across all 4 envs; DB-less (`env.database: off`) with `ingressController.installCRDs: false` (ArgoCD applies the chart `crds/` bundle via `--include-crds`); proxy TLS via a cert-manager leaf `kong-proxy`/`kong-proxy-cert` from `sca-ca` (SANs `kong.local` + `localhost`), admin/cluster certificates off; **declarative DB-less routing in git** (`infrastructure/kong/manifests/`: `Ingress kong-demo` on `ingressClassName: kong` + a `request-termination` `KongPlugin`), the reference the service charts follow; proxy NodePort 30080/30443 (local) / LoadBalancer (dev/qa/prod), 1 replica (local/dev) / 2 + PDB + soft anti-affinity (qa/prod); smoke = gateway Deployment Ready + `KONG_DATABASE=off` + IngressClass `kong` + `configuration.konghq.com` CRDs `Established` + `Certificate/kong-proxy` Ready + `GET https://kong.local/demo` → 200 (`make smoke COMPONENT=kong`) | `feat/phase-8` (PR) | [#13](https://github.com/sca-templates/infra-kubernetes/issues/13) |
| 2026-10-13 | multidict in the checkov lockfile (CI) | GHSA-54p9-h82j-f925 (CVSS 5.3) against `multidict==6.7.1`, fixed in `6.9.1`, failed the `Security` gate once the shared scan became the gate. `6.9.1` shipped 2026-09-21, after the lockfile's `--exclude-newer 2026-09-16T00:00:00Z` cutoff, so the cutoff moves to `2026-09-22T00:00:00Z` and the package is named with `--upgrade-package multidict` — without that flag `uv pip compile` keeps `6.7.1` as a preference and recompiles unchanged. Two-hunk diff: the cutoff in the generated header plus the `multidict==6.9.1` entry; `checkov` stays `3.3.16`, its IaC baseline is untouched, and no `IgnoredVulns` added (the only remaining advisory is the documented `ecdsa` one). Reproduced with `osv-scanner 2.5.1` against the lockfile: the pre-bump file fails with the advisory, the bumped one exits 0 with `No issues found`. Procedure in [security.md](security.md) | `feat/cicd` (PR) | — |
| 2026-10-02 | gitpython in the checkov lockfile (CI) | GHSA-59cr-6r3x-644w (CVSS 6.1) published against `gitpython==3.1.61` and fixed in `3.1.62` failed the `Security` gate. Unlike the urllib3 bump nine days earlier, the fix **predates** the lockfile's `--exclude-newer 2026-09-16T00:00:00Z` cutoff (`3.1.62` shipped 2026-09-07), so the cutoff stays put and only `--upgrade-package gitpython` is needed: the resolver could already see the fixed version, and `3.1.61` was surviving purely as a `uv pip compile` preference. Three-line diff, header untouched; `gitdb==4.0.12` still satisfies gitpython's range, `checkov` stays `3.3.16`, its IaC baseline is untouched, and no `IgnoredVulns` added (the only remaining advisory is the documented `ecdsa` one). Reproduced with `osv-scanner 2.3.1` against the two lockfiles: the pre-bump file fails with the advisory, the bumped one exits 0 with `No issues found`. Both cutoff cases now documented in [security.md](security.md) | `fix/release-bot` (PR) | — |
| 2026-09-30 | Release `latest` pointer (CI) | The previous `hold` job did not hold: it sent `make_latest=false` for `v0.10.1`, exited 0, and `GET /releases/latest` still answered `v0.10.1` — that parameter **stores no pointer**, and `latest` falls back to "the most recent non-prerelease, non-draft release by `created_at`", which a just-published release always is (the shared flow's tag force-push even refreshes its `created_at`: 17:20:28 vs `published_at` 17:17:05). Measured in a scratch repo: `{"make_latest":"false"}` on the newest → still newest; `{"make_latest":"legacy"}` → also newest; `{"make_latest":"true"}` on the older one → the pointer moves ✅, and publishing again clears it, so it must be re-asserted every release. Replaced by two local jobs: `capture` (parallel, snapshots the previous `latest` excluding the tag this push is about to cut, so a re-run cannot mistake the new release for the old one) and `finalize` (publishes off `latest`, re-designates the captured release, then re-reads `/releases/latest` and fails the run on a mismatch). `Release promote` stays the only thing that moves `latest` forward, and now refuses to move it backwards: since `finalize` parks the pointer on the previous release, an older tag is the everyday input, so the workflow compares version order (`sort -V`, not a string compare — `v0.10.0` < `v0.9.0` lexically) against the current `latest` and fails on a regression. Windows accepted: a few seconds where the new release is `latest` (see [versioning.md](versioning.md)) | `fix/release-bot` (PR) | — |
| 2026-09-30 | urllib3 in the checkov lockfile (CI) | three advisories published against `urllib3==2.7.0` (GHSA-8988-9cw3-xx77, GHSA-gh4c-6fx4-qh6g, GHSA-vxq7-64xx-v4gw, all fixed in `2.8.0`) failed the `Security` gate. `2.8.0` was released 2026-09-15, after the lockfile's `--exclude-newer 2026-09-02T14:59:08Z` cutoff, so the cutoff moves to `2026-09-16T00:00:00Z` and the package is named with `--upgrade-package urllib3` — without that flag `uv pip compile` keeps `2.7.0` as a preference and recompiles unchanged. Six-line diff: the cutoff in the generated header plus the `urllib3==2.8.0` entry; checkov stays `3.3.16` and its IaC baseline is untouched; no `IgnoredVulns` added (the only remaining advisory is the documented `ecdsa` one). Procedure documented in [security.md](security.md) | `fix/release-bot` (PR) | — |
| 2026-09-30 | Release `latest` hold (CI) | `release-please` cannot express "publish without claiming `latest`" (`make_latest` defaults to `true`) and the shared flow's tag force-push published the draft, so every release went out public *and* `latest` and `Release promote` was unreachable (0 runs, its `isDraft` guard could never pass). Local `hold` job now publishes with `make_latest=false` in one PATCH after the shared flow, and `Release promote` only moves the pointer (idempotent). Fix is local on purpose; the same command is owed to `CI-CD-Templates` (see [versioning.md](versioning.md)) | branch (PR) | — |
| 2026-09-27 | redis-operator | deployed — chart `ot-container-kit/redis-operator` 0.26.1 from `https://ot-container-kit.github.io/helm-charts` (operator 0.26.0, `quay.io/opstree/redis-operator`); the documented `charts.ot-container-kit.io` host is `NXDOMAIN` upstream and was replaced by the maintainers' GitHub Pages repo as an operator app in ns `data` (shared with the CRs it reconciles), appset wave -10 across all 4 envs; cluster-wide watch (`watchNamespace: ""` → no `WATCH_NAMESPACE`) so the Phase 12 Redis CRs can live in `data`; webhook off, no PDB, image tag pinned `v0.26.0`; 4 `redis.redis.opstreelabs.in` CRDs `Established`; smoke = operator Deployment Ready + the 4 CRDs `Established` + a throwaway `Redis` CR honored (StatefulSet ready + `PING` → `PONG`) (`make smoke COMPONENT=redis-operator`) | `feat/phase-7` (PR) | [#12](https://github.com/sca-templates/infra-kubernetes/issues/12) |
| 2026-09-27 | asteval override (CI) | checkov lockfile compiled through `.github/asteval-override.txt` so `asteval==1.0.10` is hash-pinned past checkov's `==1.0.6` pin; the two `IgnoredVulns` for GHSA-89v8-rhwq-hf77 / GHSA-9w56-46f6-3qhx are gone; no `pip` Dependabot watch (it rewrote the override and re-resolved the closure past checkov's own constraints); `release-gate` calls the reusable unconditionally so the required `release-gate / release-gate` context is reported on bot PRs instead of hanging (see [security.md](security.md), [ci-cd.md](ci-cd.md)) | `dependabot/pip/dot-github/pip-7934000b13` (PR) | [#73](https://github.com/sca-templates/infra-kubernetes/issues/73) |
| 2026-09-26 | Release promotion (CI) | release PR merge cuts the signed tag and leaves the release as a **draft**; `release-publish.yml` (manual) publishes it after the tag's release-bot signature verifies, so the `latest` pointer only moves on a human go/no-go. The draft did not survive the shared flow's tag force-push, so the rule was not enforced — corrected by the 2026-09-30 row above (see [versioning.md](versioning.md)) | branch (PR) | — |
| 2026-09-26 | strimzi | deployed — chart `strimzi/strimzi-kafka-operator` 1.2.0 (operator 1.2.0, quay.io/strimzi) as an operator app in ns `strimzi`, appset wave -10 across all 4 envs; `watchAnyNamespace: true` so the Phase 11 Kafka CRs can live in `data`; 10 `kafka.strimzi.io` + `core.strimzi.io` CRDs `Established`; smoke = operator Deployment Ready + `STRIMZI_NAMESPACE=*` + 10 CRDs `Established` (`make smoke COMPONENT=strimzi`) | `feature/phase-6` (PR) | [#11](https://github.com/sca-templates/infra-kubernetes/issues/11) |
| 2026-09-08 | cloudnative-pg | deployed — chart `cloudnative-pg/cloudnative-pg` 0.29.0 (operator 1.30.0, cloudnative-pg.github.io/charts) as an operator app in ns `cloudnative-pg`, appset wave -10 across all 4 envs; `config.clusterWide` watch so the `data` datastores land at Phase 10, monitoring off until Phase 14; smoke = operator Deployment Ready + 11 `postgresql.cnpg.io` CRDs `Established` (`make smoke COMPONENT=cloudnative-pg`) | `feature/phase-5` (PR) | [#10](https://github.com/sca-templates/infra-kubernetes/issues/10) |
| 2026-09-08 | linkerd-crds | deployed — chart `linkerd/linkerd-crds` 1.8.0 (helm.linkerd.io/stable) as a CRD-only app in ns `linkerd`, appset wave -10 across all 4 envs; `enableHttpRoutes: true` (chart default); smoke = the `linkerd.io` + `policy.linkerd.io` CRD groups present + `Established` (`make smoke COMPONENT=linkerd-crds`) | `feature/phase-4` (PR) | [#9](https://github.com/sca-templates/infra-kubernetes/issues/9) |
| 2026-09-08 | external-secrets | deployed — ESO chart 2.10.0, `ClusterSecretStore vault` Ready (k8s-auth `external-secrets`, TLS via `vault-tls`), smoke = throwaway ExternalSecret pulling `secret/keycloak/admin` → `SecretSynced` + data verified; short `refreshInterval` (5m); appset wave -10 across all 4 envs | `feature/phase-3` (PR) | [#8](https://github.com/sca-templates/infra-kubernetes/issues/8) |
| 2026-09-08 | vault | deployed — HA raft trio (leader + 2 standbys), TLS via cert-manager leaf (`vault-tls`, SANs for `vault-active` + headless), readiness/liveness probes HTTPS, seed idempotent HA-aware; `make smoke COMPONENT=vault` → initialized=true sealed=false | `feature/phase-2` (PR) | [#7](https://github.com/sca-templates/infra-kubernetes/issues/7) |
| 2026-09-07 | Release triggers path-scoped (CI) | releases only for `feat`/`fix` touching the platform surface (`exclude-paths` in `.release-please-config.json`); release-please runs on `push` only; dispatch re-signs tags only with both inputs | branch (PR) | — |
| 2026-09-05 | Release automation swap (CI) | release PRs/tags authored by `sca-bot-release[bot]` GitHub App token | `chore/release-app` (PR) | — |
| 2026-09-05 | PR branch sync (CI) | queued PRs auto-merged with new `main` | `2b9da65` (squash of PR #38) | — |
| 2026-09-05 | Release gate (CI) | human PRs blocked while a release PR is open | `a2e7937` (squash of PR #39) | — |
| 2026-09-04 | Release tag signing (CI) + re-sign | signed tag `v0.1.0` green | `f8d50f4` (squash of PR #35), re-sign via workflow dispatch | — |
| 2026-09-04 | Release `v0.1.0` (first release) | release + tag shipped | `0e39a99` (squash of PR #33) | — |
| 2026-09-04 | Release gating fix (CI) | release PRs pass static gates | `3c658fe` (squash of PR #34) | — |
| 2026-09-04 | Release automation (CI) | static gates green | `26359b6` (squash of PR #32) | — |
| 2026-09-01 | Knowledge base (docs) | scaffold + docs green | `dbbf5f4` | — |
| 2026-09-06 | cert-manager | deployed — `sca-ca` ClusterIssuer Ready, leaf Certificate smoke green, all 4 env overlays + appset wave -20 | `feature/phase-1` (PR) | [#6](https://github.com/sca-templates/infra-kubernetes/issues/6) |
| 2026-09-06 | Cluster smoke (CI) | `pr-cluster.yml` shipped — selective on PRs + vigilance on `push: main`, informative until stable; `bootstrap/smoke-ci.sh` owns boot→apply→wait→run→diagnose→teardown | `feature/phase-1` (PR) | — |
| 2026-09-06 | checkov baseline gate (CI) | `.github/checkov-baseline.json` records the local-git-server pod findings; `security.yml` gates **new** IaC findings from Phase 1, re-evaluated at Phase 18 | `feature/phase-1` (PR) | — |
| 2026-09-08 | Cluster smoke (CI) | `pr-cluster.yml` now PR-only + manual `workflow_dispatch`, required `Smoke` branch-protection check on `main` (no `push` smoke); wait tolerates unassessed (`Missing`) health | branch | — |
| 2026-09-08 | App-of-apps on local serve (Phase 1) | `bootstrap/render-served-apps.sh` renders `argocd/apps-local.yaml` onto the git serve so the root app parses it (`ComparisonError` cleared); Phase 0.0 `automated.enabled=false` override dropped; `platform-root-local` `Synced` + `Healthy`, cert-manager smoke green | branch | — |

Phases 0.x scaffold the repository and are not delivery projects; they are
recorded here for continuity. From Phase 1, each row is appended in the same
commit that lands the component. The first release (`v0.1.0`) covers the whole
pre-release history as a signed baseline — see
[versioning.md](versioning.md).

## Rules, out-of-plan and placeholders

- **Not every task belongs to a project/milestone.** Issues raised by bots
  (dependabot, Copilot code review) or by external developers, and ad-hoc debt, are
  tracked on the board, may carry a milestone/project label only when it
  applies, and are **not forced into this roadmap**. They resolve
  independently and do not block promotion.
- **One project = one component, landed via reviewed PRs.** A component often
  ships as a single PR, but the number of PRs/commits is a judgment call
  driven by the change — grouping is not a rule. A component that does not
  turn green **rolls back** — no fix chains, no ad-hoc
  `ignoreDifferences`/SSA patches, nothing deployed by hand after
  `make bootstrap`.
- **Milestones are optional** — a project without natural phases has its issues
  directly under it (no `### Milestone` heading).
- **Issue numbers are real links** — created when the repo was published; the
  board and issues are the tracker, this file is the index.
- **`[x]` marks completion**; timestamps live in the commits (git history), not
  in the marks.

## Change flow

A change lands via PR → CI (static; selective cluster smoke from Phase 1) → human
review → merge → each environment's ArgoCD applies it per its sync policy. See
[workflow.md](workflow.md) for the full flow and the escalation (rollback) gate.
