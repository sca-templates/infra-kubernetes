# Project: Implement CloudNativePG

Area: Data · Wave -10 · Environments: local→dev→qa→prod
Depends on: — (operator only, wave -10)
Project done when: `cloudnative-pg` operator `Running`; a `Cluster` CR review
(`postgres-app`) can be created (data project #10 waits on it).

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

Rollout note (local, one-off cluster hygiene): the 11 orphaned
`postgresql.cnpg.io` CRDs left by the 2026-09-02 pre-restart bulk install
(`helm.sh/resource-policy: keep`, managed by no app) must be removed from
`local` before the chart app converges to `Synced` — the same leftover-CRD
condition that wedged linkerd-crds (see `docs/architecture.md` deviations log).
