# Project: Implement Velero

Area: Delivery & Resilience · Wave 80 · Environments: local→dev→qa→prod
Depends on: Floci S3 (local dev/CI tooling) for the backup backend.
Project done when: Velero installed; a scheduled backup of a test namespace runs;
restore proves the backup (`Backup` `Completed` + `Restore` succeeds).

## Milestone M1 — Install

M1 done when: Velero pod `Running`, backup location available.

- [x] Issue #23 · Deploy `vmware-tanzu/velero` (local M1)
  Depends on: Floci S3 (local dev/CI tooling)
  - [x] `infrastructure/velero/` values-base + overlays for 4 envs
        - [x] `envs/local` (Floci S3); `dev`/`qa`/`prod` are stubs pending real S3
        - Commits: `feat(velero): add chart reference and per-env overlays`
  - [x] backup storage location → Floci S3 (local)
        Commits: `feat(velero): floci backup location`
  - [x] smoke: real `Backup` of a test namespace reaches `Completed`
        `bootstrap/smoke-velero.sh` also asserts the BSL is `Available` and the
        `velero-critical-namespaces` schedule exists.
        Commits: `test(velero): backup smoke`
  - [x] docs: Work Log row + catalog Status → deployed
        Commits: `docs(velero): mark deployed`
  Issue done when: backup of a test namespace `Completed`.

## Milestone M2 — Restore

M2 done when: a `Restore` from the completed backup succeeds.

- [ ] Issue #30 · Restore proof
  - [ ] `velero restore` from the completed backup
        Commits: `feat(velero): restore flow`
  - [ ] smoke: restored namespace has its resources back
        Commits: `test(velero): restore smoke`
  - [ ] docs: runbook/troubleshooting note in [workflow.md](../workflow.md)
        Commits: `docs(velero): restore runbook`
  Issue done when: restore round-trip succeeds.
