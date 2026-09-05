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
> Phase 1 deliverable that lands with cert-manager and then runs
> automatically for every subsequent component — each project's "one
> functional smoke" (in the per-project gate above) becomes the `pr-cluster`
> smoke command. No per-component workflow wiring is needed beyond the
> component's smoke command in `bootstrap/smoke-target.sh`. Profile: `local`
> (see [ci-cd.md](ci-cd.md)).

## Projects (index)

| Project | Area | Wave | Milestones | Issues | Status |
| --- | --- | --- | --- | --- | --- |
| [cert-manager](roadmap/cert-manager.md) | Security & Identity | -20 | — | [#6](https://github.com/sca-templates/infra-kubernetes/issues/6) | pending |
| [vault](roadmap/vault.md) | Security & Identity | 0 | M1 bootstrap · M2 seed · M2 integration | [#7](https://github.com/sca-templates/infra-kubernetes/issues/7) · [#24](https://github.com/sca-templates/infra-kubernetes/issues/24) · [#25](https://github.com/sca-templates/infra-kubernetes/issues/25) · [#26](https://github.com/sca-templates/infra-kubernetes/issues/26) | pending |
| [external-secrets](roadmap/external-secrets.md) | Security & Identity | -10 | — | [#8](https://github.com/sca-templates/infra-kubernetes/issues/8) | pending |
| [linkerd-crds](roadmap/linkerd-crds.md) | Edge & Mesh | -10 | — | [#9](https://github.com/sca-templates/infra-kubernetes/issues/9) | pending |
| [cloudnative-pg](roadmap/cloudnative-pg.md) | Data | -10 | — | [#10](https://github.com/sca-templates/infra-kubernetes/issues/10) | pending |
| [strimzi](roadmap/strimzi.md) | Data | -10 | — | [#11](https://github.com/sca-templates/infra-kubernetes/issues/11) | pending |
| [redis-operator](roadmap/redis-operator.md) | Data | -10 | — | [#12](https://github.com/sca-templates/infra-kubernetes/issues/12) | pending |
| [kong](roadmap/kong.md) | Edge & Mesh | 20 | M1 dedicated app | [#13](https://github.com/sca-templates/infra-kubernetes/issues/13) | pending |
| [linkerd](roadmap/linkerd.md) | Edge & Mesh | 30 | M1 control plane | [#14](https://github.com/sca-templates/infra-kubernetes/issues/14) | pending |
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
| 2026-09-05 | Release automation swap (CI) | release PRs/tags authored by `sca-bot-release[bot]` GitHub App token | `chore/release-app` (PR) | — |
| 2026-09-05 | PR branch sync (CI) | queued PRs auto-merged with new `main` | `2b9da65` (squash of PR #38) | — |
| 2026-09-05 | Release gate (CI) | human PRs blocked while a release PR is open | `a2e7937` (squash of PR #39) | — |
| 2026-09-04 | Release tag signing (CI) + re-sign | signed tag `v0.1.0` green | `f8d50f4` (squash of PR #35), re-sign via workflow dispatch | — |
| 2026-09-04 | Release `v0.1.0` (first release) | release + tag shipped | `0e39a99` (squash of PR #33) | — |
| 2026-09-04 | Release gating fix (CI) | release PRs pass static gates | `3c658fe` (squash of PR #34) | — |
| 2026-09-04 | Release automation (CI) | static gates green | `26359b6` (squash of PR #32) | — |
| 2026-09-01 | Knowledge base (docs) | scaffold + docs green | `dbbf5f4` | — |
| *next* | cert-manager | *pending* | | [#6](https://github.com/sca-templates/infra-kubernetes/issues/6) |

Phases 0.x scaffold the repository and are not delivery projects; they are
recorded here for continuity. From Phase 1, each row is appended in the same
commit that lands the component. The first release (`v0.1.0`) covers the whole
pre-release history as a signed baseline — see
[versioning.md](versioning.md).

## Rules, out-of-plan and placeholders

- **Not every task belongs to a project/milestone.** Issues raised by bots
  (dependabot, scorecard) or by external developers, and ad-hoc debt, are
  tracked on the board, may carry a milestone/project label only when it
  applies, and are **not forced into this roadmap**. They resolve
  independently and do not block promotion.
- **One project = one component = one commit = one PR = one review.** A
  component that does not turn green **rolls back** — no fix chains, no ad-hoc
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
