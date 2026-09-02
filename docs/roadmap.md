# Roadmap

The delivery plan for the `sca` platform on Kubernetes, one component per
phase, each with a human-reviewed functional gate. This file is the **source
of truth for the delivery plan**; the work items themselves are tracked in
GitHub (**Projects board, Milestones and Issues**) and linked from the rows
below. `status.md` is the source of truth for *what is deployed right now*
and the known gaps.

**Rule: docs move with their component.** A phase that lands appends a **Work
Log** row (see [Work log](#work-log)) and updates this file's Status column +
`docs/architecture.md` (Status, deviations log) in the **same commit**.

## Model

- **One component = one phase = one commit = one PR = one review.**
- A component that does not turn green **rolls back** — there are no
  `fix(...)` chains, no ad-hoc `ignoreDifferences`/SSA patches, nothing
  deployed by hand after `make bootstrap`.
- Sync-waves are assigned in `docs/architecture.md`; a new component gets a
  wave ≥10 apart from its dependencies.
- GitHub linkage: each phase below maps to an **Issue** (and, once promoted, a
  **Milestone**). The Projects board groups phases by environment
  (`local` → `dev` → `qa` → `prod`).

## Roadmap

The 18 phases and their gates. `Status` is `pending` until the phase's gate is
verified green, then `done` (and the Work Log row appended).

| Phase | Component | Functional gate | GitHub issue | Status |
| --- | --- | --- | --- | --- |
| 1 | cert-manager + `sca-ca` ClusterIssuer | test Certificate Ready | [#1](https://github.com/sca-templates/infra-kubernetes/issues/1) | pending |
| 2 | Vault (raft) | pod Ready, `vault status` initialized + unsealed, TLS via cert-manager, idempotent seed | [#2](https://github.com/sca-templates/infra-kubernetes/issues/2) | pending |
| 3 | external-secrets + ClusterSecretStore | smoke ExternalSecret → `SecretSynced` | [#3](https://github.com/sca-templates/infra-kubernetes/issues/3) | pending |
| 4 | linkerd-crds | CRDs present, app Healthy | [#4](https://github.com/sca-templates/infra-kubernetes/issues/4) | pending |
| 5 | cloudnative-pg | `Cluster` CRD accepted | [#5](https://github.com/sca-templates/infra-kubernetes/issues/5) | pending |
| 6 | strimzi | `Kafka`/`KafkaNodePool` CRDs | [#6](https://github.com/sca-templates/infra-kubernetes/issues/6) | pending |
| 7 | redis-operator | `Redis` CRD | [#7](https://github.com/sca-templates/infra-kubernetes/issues/7) | pending |
| 8 | Kong (dedicated app) | echo service via NodePort 30080, admin Healthy | [#8](https://github.com/sca-templates/infra-kubernetes/issues/8) | pending |
| 9 | Linkerd control plane (script) | mTLS identity up | [#9](https://github.com/sca-templates/infra-kubernetes/issues/9) | pending |
| 10 | postgres-app + keycloak-db | clusters Ready, `psql SELECT 1` | [#10](https://github.com/sca-templates/infra-kubernetes/issues/10) | pending |
| 11 | Kafka CR + SCRAM | create topic + produce/consume smoke | [#11](https://github.com/sca-templates/infra-kubernetes/issues/11) | pending |
| 12 | Redis CR | `SET`/`GET` | [#12](https://github.com/sca-templates/infra-kubernetes/issues/12) | pending |
| 13 | Keycloak | admin API login, valid RS256 JWT | [#13](https://github.com/sca-templates/infra-kubernetes/issues/13) | pending |
| 14 | kube-prometheus-stack | Prometheus + Grafana up, targets, radar rules | [#14](https://github.com/sca-templates/infra-kubernetes/issues/14) | pending |
| 15 | Loki + Alloy | logs queryable | [#15](https://github.com/sca-templates/infra-kubernetes/issues/15) | pending |
| 16 | Tempo | OTLP up, trace smoke | [#16](https://github.com/sca-templates/infra-kubernetes/issues/16) | pending |
| 17 | MinIO (local-only, wave 70) | health endpoint OK | [#17](https://github.com/sca-templates/infra-kubernetes/issues/17) | pending |
| 18 | Velero (wave 80) | install + schedule + backup/restore of a small namespace | [#18](https://github.com/sca-templates/infra-kubernetes/issues/18) | pending |

> **Issue numbers are placeholders.** They become valid links once this
> repository is published to GitHub and per-phase issues are created. Until
> then they point at the future `sca-templates/infra-kubernetes` issues.

## Per-component Definition of Done (local)

Apply this checklist to every phase before it flips to `done`. The checklist
for *adding* a component lives in
[onboarding-new-service.md](onboarding-new-service.md); the DoD below is the
release gate per phase.

- Component `Synced` + `Healthy` in ArgoCD.
- Pods `Running`, no `CrashLoopBackOff`/`ImagePullBackOff` after 2+ min stable.
- `ExternalSecret` → `SecretSynced` where applicable.
- One functional smoke (the row above).
- `make status` shows no new `Degraded`.
- Single commit, human-reviewed; docs updated in the same commit (Work Log
  below + `architecture.md`/`status.md`).

## Work log

Reverse-chronological record of landed components — the delivery plan's
history. Each entry: phase, component, gate result, commit, and the GitHub
issue it closed.

| Date | Phase | Component | Gate result | Commit | Issue |
| --- | --- | --- | --- | --- | --- |
| 2026-09-01 | 0.1 | Knowledge base (docs) | scaffold + docs green | `dbbf5f4` | — |
| *next* | 1 | cert-manager | *pending* | | #1 |

> Phases 0.x scaffold the repo and are not "components" with a gate; they are
> recorded here for continuity. From Phase 1, each row is appended by the
> phase that lands (not planned ahead of time).
