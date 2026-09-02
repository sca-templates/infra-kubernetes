# Project: Implement Velero

Area: Delivery & Resilience · Wave 80 · Environments: local→dev→qa→prod
Depends on: minio (#17, local) for the backup backend.
Project done when: Velero installed; a scheduled backup of a test namespace runs;
restore proves the backup (`Backup` `Completed` + `Restore` succeeds).

## Milestone M1 — Install

M1 done when: Velero pod `Running`, backup location available.

- [ ] Issue #18 · Deploy `vmware-tanzu/velero`
  Depends on: minio (#17)
  - [ ] `infrastructure/velero/` values-base + overlays for 4 envs
        - [ ] envs/local, dev, qa, prod
        - Commits: `feat(velero): add chart reference and per-env overlays`
  - [ ] backup storage location → MinIO S3 (local)
        Commits: `feat(velero): minio backup location`
  - [ ] smoke: `velero backup create` a test namespace, `Backup` `Completed`
        Commits: `test(velero): backup smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(velero): mark deployed`
  Issue done when: backup of a test namespace `Completed`.

## Milestone M2 — Restore

M2 done when: a `Restore` from the completed backup succeeds.

- [ ] Issue #18-2 · Restore proof
  - [ ] `velero restore` from the completed backup
        Commits: `feat(velero): restore flow`
  - [ ] smoke: restored namespace has its resources back
        Commits: `test(velero): restore smoke`
  - [ ] docs: runbook/troubleshooting note in [workflow.md](../workflow.md)
        Commits: `docs(velero): restore runbook`
  Issue done when: restore round-trip succeeds.
