# Roadmap — Delivery Plan

Context: `infra-kubernetes`, the GitOps source of truth for the `sca` platform
on Kubernetes. Board: [GitHub Projects](https://github.com/sca-templates/infra-kubernetes/projects) · Milestones: per project below · Issues: `#N` placeholders until the repo is published.

This file is the **index and source of truth for the delivery plan**. Per-project detail
lives in `docs/roadmap/<project>.md`; what is deployed *now* lives in
[status.md](status.md); the component catalog and sync-waves live in
[architecture.md](architecture.md).

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

## Projects (index)

| Project | Area | Wave | Milestones | Issues | Status |
| --- | --- | --- | --- | --- | --- |
| [cert-manager](roadmap/cert-manager.md) | Security & Identity | -20 | — | #1 | pending |
| [vault](roadmap/vault.md) | Security & Identity | 0 | M1 bootstrap · M2 seed · M3 integration | #2-1…#2-3 | pending |
| [external-secrets](roadmap/external-secrets.md) | Security & Identity | -10 | — | #3 | pending |
| [linkerd-crds](roadmap/linkerd-crds.md) | Edge & Mesh | -10 | — | #4 | pending |
| [cloudnative-pg](roadmap/cloudnative-pg.md) | Data | -10 | — | #5 | pending |
| [strimzi](roadmap/strimzi.md) | Data | -10 | — | #6 | pending |
| [redis-operator](roadmap/redis-operator.md) | Data | -10 | — | #7 | pending |
| [kong](roadmap/kong.md) | Edge & Mesh | 20 | M1 dedicated app | #8 | pending |
| [linkerd](roadmap/linkerd.md) | Edge & Mesh | 30 | M1 control plane | #9 | pending |
| [postgres-app](roadmap/postgres-app.md) | Data | 40 | M1 cluster · M2 keycloak-db | #10 | pending |
| [kafka](roadmap/kafka.md) | Data | 40 | M1 CR + SCRAM | #11 | pending |
| [redis](roadmap/redis.md) | Data | 40 | — | #12 | pending |
| [keycloak](roadmap/keycloak.md) | Security & Identity | 50 | M1 deploy · M2 realm | #13 | pending |
| [kube-prometheus-stack](roadmap/kube-prometheus-stack.md) | Observability | 60 | M1 stack · M2 radar | #14 | pending |
| [loki](roadmap/loki.md) | Observability | 60 | M1 loki · M2 alloy | #15 | pending |
| [tempo](roadmap/tempo.md) | Observability | 60 | — | #16 | pending |
| [minio](roadmap/minio.md) | Delivery & Resilience | 70 | — | #17 | pending |
| [velero](roadmap/velero.md) | Delivery & Resilience | 80 | M1 install · M2 backup/restore | #18 | pending |

## Work log (global, reverse-chronological)

| Date | Project | Gate | Commit | Issue |
| --- | --- | --- | --- | --- |
| 2026-09-01 | Knowledge base (docs) | scaffold + docs green | `dbbf5f4` | — |
| *next* | cert-manager | *pending* | | #1 |

Phases 0.x scaffold the repository and are not delivery projects; they are
recorded here for continuity. From Phase 1, each row is appended in the same
commit that lands the component.

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
- **Issue numbers are placeholders** (`#N`): they become valid links once this
  repository is published to GitHub and per-phase issues are created.
- **`[x]` marks completion**; timestamps live in the commits (git history), not
  in the marks.

## Change flow

A change lands via PR → CI (static; selective smoke in later phases) → human
review → merge → each environment's ArgoCD applies it per its sync policy. See
[workflow.md](workflow.md) for the full flow and the escalation (rollback) gate.
