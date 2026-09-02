# Project: Implement CloudNativePG

Area: Data · Wave -10 · Environments: local→dev→qa→prod
Depends on: — (operator only, wave -10)
Project done when: `cloudnative-pg` operator `Running`; a `Cluster` CR review
(`postgres-app`) can be created (data project #10 waits on it).

No natural phases → issues directly under the project.

- [ ] Issue #5 · Deploy `cloudnative-pg/cloudnative-pg`
  Depends on: —
  - [ ] `infrastructure/cloudnative-pg/` values-base + overlays for 4 envs
        - [ ] envs/local, dev, qa, prod
        - Commits: `feat(cloudnative-pg): add chart reference and per-env overlays`
  - [ ] registry appset element (wave -10)
        Commits: `feat(cloudnative-pg): register in apps appset (wave -10)`
  - [ ] smoke: operator pod `Running`, CRD groups present
        Commits: `test(cloudnative-pg): operator smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(cloudnative-pg): mark deployed`
  Issue done when: operator pod `Running` + CRDs present.
