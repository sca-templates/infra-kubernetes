# Project: Implement CloudNativePG

Area: Data · Wave -10 · Environments: local→dev→qa→prod
Depends on: — (operator only, wave -10)
Project done when: `cloudnative-pg` operator `Running`; a `Cluster` CR review
(`postgres-app`) can be created (data project #15 waits on it).

No natural phases → issues directly under the project.

- [x] Issue #10 · Deploy `cloudnative-pg/cloudnative-pg`
  Depends on: —
  - [x] `infrastructure/cloudnative-pg/` values-base + overlays for 4 envs
        - [x] envs/local, dev, qa, prod
        - Commits: `feat(cloudnative-pg): add chart reference and per-env overlays`
  - [x] registry appset element (wave -10)
        Commits: `feat(cloudnative-pg): register in apps appset (wave -10)`
  - [x] smoke: operator pod `Running`, CRD groups present
        Commits: `test(cloudnative-pg): operator smoke`
  - [x] docs: Work Log row + catalog Status → deployed
        Commits: `docs(cloudnative-pg): mark deployed`
  Issue done when: operator pod `Running` + CRDs present.

## Backup + PITR (Phase B)

The operator milestone is complete. The data-protection layer is a separate
Phase B deliverable, tracked in [backups.md](../backups.md) and the global Work
Log.

- [x] `barmanObjectStore` + continuous WAL archiving on `postgres-app` and
      `keycloak-db` (all four envs)
- [x] daily `ScheduledBackup`s with environment retention (local `7d`,
      dev/qa `30d`, prod `90d`)
- [x] backup credentials projected by ESO from `secret/cnpg/<env>`
- [x] `bootstrap/smoke-postgres-app.sh`: PITR restore on `postgres-app` and
      latest-backup restore on `keycloak-db`
- [ ] live green run of the restore smoke on the Floci EKS substrate

Rollout note (local, one-off cluster hygiene): the orphaned `postgresql.cnpg.io`
CRDs left by the 2026-09-02 pre-restart bulk install were removed from `local`
before the chart app converged — the same leftover-CRD condition that wedged
linkerd-crds. The app re-created its 11 CRDs as app-owned and converged
`Synced`. The hygiene pass extended to every undeployed group of that bulk
(Strimzi, redis-operator, Kong, Prometheus, Velero); see `docs/architecture.md`
deviations log.
