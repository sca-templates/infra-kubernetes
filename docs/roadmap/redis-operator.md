# Project: Implement redis-operator

Area: Data · Wave -10 · Environments: local→dev→qa→prod
Depends on: — (operator only, wave -10)
Project done when: `redis-operator` `Running`; a `Redis` CR review shows the
CR is honored (data project #12 waits on it).

No natural phases → issues directly under the project.

- [ ] Issue #7 · Deploy `ot-container-kit/redis-operator`
  Depends on: —
  - [ ] `infrastructure/redis-operator/` values-base + overlays for 4 envs
        - [ ] envs/local, dev, qa, prod
        - Commits: `feat(redis-operator): add chart reference and per-env overlays`
  - [ ] registry appset element (wave -10)
        Commits: `feat(redis-operator): register in apps appset (wave -10)`
  - [ ] smoke: operator pod `Running`, Redis CR group present
        Commits: `test(redis-operator): operator smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(redis-operator): mark deployed`
  Issue done when: operator pod `Running` + CRD present.
