# Status: Current State and Known Gaps

An honest picture of the platform today: what is deployed where, what is being
worked on, what is intentionally absent. Anything not listed here is either in
the component catalog ([architecture.md](architecture.md)) or does not exist.

The **delivery plan** (the 18 phases, their gates and the Work Log) now lives
in [roadmap.md](roadmap.md) and is tracked on the GitHub Projects board,
Milestones and Issues.

## Current state

**Phase 5 — cloudnative-pg deployed.** Phase 0 delivered the scaffold
(Makefile, `bootstrap/`, `argocd/` with the app-of-apps pattern, the CI
workflows, the service template, this docs set) and brought the local `kind`
cluster up with ArgoCD. **Phase 1** lands cert-manager on the `local` profile
(fully-local: ArgoCD reconciles an in-cluster git serve instead of GitHub) and
ships the cluster smoke. **Phase 2** lands Vault — the secrets SSOT — as an HA
raft trio with TLS via a cert-manager leaf, an idempotent HA-aware seed, and a
green smoke. **Phase 3** lands External Secrets Operator: it projects Vault KV
into native Kubernetes `Secret`s through the `ClusterSecretStore vault`
(k8s-auth, TLS via the `vault-tls` leaf) with a short ~5 min refresh, and ships
a smoke proving a projected secret reaches `SecretSynced`. **Phase 4** lands
linkerd-crds — the service-mesh CRDs (`linkerd.io` + `policy.linkerd.io`, plus
the chart-default gateway `HTTPRoute`) in the `linkerd` namespace — a CRD-only
Application with no workloads; it is the base the Linkerd control plane
(Phase 9, wave 30) installs against. **Phase 5** lands CloudNativePG — the
PostgreSQL operator — at wave -10 in the `cloudnative-pg` namespace: chart
pinned 0.29.0 (operator 1.30.0), cluster-wide watch (`config.clusterWide`) so
the datastores can run in `data` at Phase 10, monitoring off until Phase 14,
with the 11 `postgresql.cnpg.io` CRDs all `Established`. No `Cluster` CR
exists yet (postgres-app / keycloak-db land at Phase 10). See
[ci-cd.md](ci-cd.md) for the smoke design.

| Fact | Value |
| --- | --- |
| Repository | `infra-kubernetes` (local, fully-local git serve; published to GitHub before promotion) |
| Deployed components | ArgoCD (bootstrap), cert-manager (Phase 1), Vault (Phase 2), external-secrets (Phase 3), linkerd-crds (Phase 4), cloudnative-pg (Phase 5) |
| `platform-root-local` | present, `Synced` + `Healthy` against the local git serve (`main`); Phase 0.0 `automated.enabled=false` override dropped |
| `platform-local` ApplicationSet | present, five elements (`cert-manager` wave -20, `external-secrets` + `linkerd-crds` + `cloudnative-pg` wave -10, `vault` wave 0) |
| cert-manager app | `cert-manager-local` `Synced` + `Healthy`; `sca-ca` ClusterIssuer `Ready`; leaf Certificate smoke green |
| vault app | `vault-local` `Synced` + `Healthy`; HA raft trio, TLS via `vault-tls` leaf; `make smoke COMPONENT=vault` → initialized=true sealed=false; seed idempotent and HA-aware |
| external-secrets app | `external-secrets-local` `Synced` + `Healthy`; `ClusterSecretStore vault` Ready (k8s-auth `external-secrets`, TLS via `vault-tls`); short `refreshInterval` (5m); `make smoke COMPONENT=external-secrets` → throwaway ExternalSecret `SecretSynced` + data verified |
| linkerd-crds app | `linkerd-crds-local` `Synced`, namespace `linkerd` present, CRD-only app (no workloads); `servers`/`serverauthorizations`/`serviceprofiles` + policy group all `Established`; `make smoke COMPONENT=linkerd-crds` green |
| cloudnative-pg app | `cloudnative-pg-local` `Synced` + `Healthy`; operator Deployment `cloudnative-pg` Ready (chart 0.29.0 / operator 1.30.0); 11 `postgresql.cnpg.io` CRDs present + `Established`; `make smoke COMPONENT=cloudnative-pg` green |
| git-local-serve | in-cluster git daemon (`git://<node>:9418/sca-infra.git`) `Ready` |
| Observability / smoke CI | cluster smoke `pr-cluster.yml` **shipped** (Phase 1): selective on PRs as the **required `Smoke` check** on `main` + manual `workflow_dispatch`; no `push` smoke (see [ci-cd.md](ci-cd.md)) |
| Security CI | checkov **baseline gate** active (Phase 1): `.github/checkov-baseline.json` documents the local-git-server pod findings; new IaC findings fail the PR; re-evaluated at Phase 18 (see [security.md](security.md)) |
| Release automation | **path-scoped** triggers active (see [versioning.md](versioning.md)): only `feat`/`fix` commits touching the platform surface open release PRs (`exclude-paths` in `.release-please-config.json`); release-please runs on `push: main` only, dispatch re-signs tags only with both inputs |
| dev / qa / prod clusters | pending (provisioned by terraform/ansible, outside this repo) |

## Known accepted limitations

| # | Limitation | Current behavior | To close |
| --- | --- | --- | --- |
| 1 | **Fully-local git serve (not GitHub)** | Local ArgoCD reconciles the in-cluster git serve (`git://<node>:9418`), not the GitHub repo; the serve carries a **rendered** `argocd/apps-local.yaml` (`bootstrap/render-served-apps.sh`), while the repo templates keep the `{{GIT_REPO_URL}}`/`{{GIT_TARGET_BRANCH}}` placeholders for the `make bootstrap` seam | Publish the repo and swap `GIT_REPO_URL` back to GitHub to exercise the real source-of-truth path; dev / qa / prod must render their `apps-<env>.yaml` the same way when those clusters bootstrap |
| 2 | **dev / qa / prod clusters pending** | Not provisioned (terraform/ansible outside this repo) | Provision per env; promote via `promote-test` (see [workflow.md](workflow.md)) |
| 3 | **OpenSSF Best Practices badge — silver blocked** | All silver criteria are met except `contributors_unassociated` and `bus_factor` (≥2): the project has a single maintainer (`CODEOWNERS` = `@Santiago1010`) | Achieved once a second **unassociated** contributor joins and is reflected in `CODEOWNERS` + `.github/GOVERNANCE.md`; passing badge is already achievable (see [.github/GOVERNANCE.md](../.github/GOVERNANCE.md), [docs/ci-cd.md](ci-cd.md)) |
| 4 | **OpenSSF Best Practices badge — gold blocked** | Beyond the silver gaps, gold requires `two_person_review` (≥50% of changes reviewed by someone other than the author), which is unrealisable while there is a single maintainer; all other gold criteria are Met or N/A (see [.github/SECURITY.md](../.github/SECURITY.md) security review, SPDX + copyright headers per source file) | Unblocked together with silver once a second, **unassociated** reviewer/maintainer exists; `two_person_review` then requires an explicit second reviewer on gold PRs |

## Intentional exclusions

- **No Unleash, no KafkaConnect/Debezium, no kafka-ui, no linkerd-viz
  in-cluster.** They are deliberate scope cuts of the restart plan.
- **No Consul and no Consul-k8s in-cluster** (ADR-001): native Kubernetes DNS +
  Linkerd replace it.
- **No `latest` tags, no image builds**: infrastructure pins upstream
  releases; this repo builds nothing.

## Read this doc

- Before any change, check the [roadmap](roadmap.md) and the [deviations
  log](architecture.md#deviations-log): they are the normative record.
- `local` is the demo/CI substrate; treat everything it runs as the minimal
  but *complete* platform, not as a reduced copy.
