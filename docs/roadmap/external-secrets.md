# Project: Implement External Secrets

Area: Security & Identity · Wave -10 · Environments: local→dev→qa→prod
Depends on: vault (#2) — ClusterSecretStore consumes Vault; syncs land after Vault is seeded.
Project done when: `ClusterSecretStore vault` Ready; a projected Secret is
`Synced` with its Vault KV source; syncs use short refresh (~5 min).

No natural phases → issues directly under the project.

- [ ] Issue #3 · Deploy `external-secrets/external-secrets` + `ClusterSecretStore`
  Depends on: vault (#2)
  - [ ] `infrastructure/external-secrets/` values-base + overlays for 4 envs
        - [ ] envs/local, dev, qa, prod
        - Commits: `feat(external-secrets): add chart reference and per-env overlays`
  - [ ] registry appset element (wave -10)
        Commits: `feat(external-secrets): register in apps appset (wave -10)`
  - [ ] `ClusterSecretStore vault` (k8s-auth) referencing Vault
        Commits: `feat(external-secrets): vault cluster secret store`
  - [ ] smoke: one `ExternalSecret` pulling a KV secret → `Synced`
        Commits: `test(external-secrets): kv projection smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(external-secrets): mark deployed`
  Issue done when: store `Ready` + external secret `Synced`.
