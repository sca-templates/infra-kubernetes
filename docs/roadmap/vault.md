# Project: Implement Vault

Area: Security & Identity · Wave 0 · Environments: local→dev→qa→prod
Depends on: cert-manager (#1)
Project done when: pod `Ready`; `vault status` initialized + unsealed; TLS via
cert-manager; idempotent seed; ESO consumes (integration with #3).

## Milestone M1 — Operator bootstrap

M1 done when: chart deployed, pod `Running`, no `CrashLoopBackOff`.

- [ ] Issue #2-1 · Deploy `hashicorp/vault` (raft/HA)
  Depends on: —
  - [ ] `infrastructure/vault/` values-base + overlays for 4 envs
        - [ ] envs/local, dev, qa, prod
        - Commits: `feat(vault): add chart reference and per-env overlays`
  - [ ] registry appset element (wave 0)
        Commits: `feat(vault): register in apps appset (wave 0)`
  - [ ] raft HA storage: replicas local/dev=1, qa/prod=3
        Commits: `feat(vault): configure raft HA storage`
  Issue done when: app `Synced`/`Healthy` + pod `Running`.

## Milestone M2 — Seed + integration

M2 done when: unsealed; ESO consumes; TLS ok.

- [ ] Issue #2-2 · Initialize + unseal (idempotent)
  - [ ] unseal keys → `.secrets/` (never git)
        Commits: —
  - [ ] `bootstrap/seed-vault.sh` idempotent
        Commits: `feat(vault): idempotent seed script`
  Issue done when: `vault status` → initialized=true, sealed=false.

- [ ] Issue #2-3 · Kubernetes auth + `ClusterSecretStore` (ESO integration)
  - [ ] ClusterRole / k8s-auth role
        Commits: `feat(vault): k8s auth role for ESO`
  - [ ] seed KV v2 path under `secret/<service>/<env>`
        Commits: `feat(vault): seed KV v2 secrets layout`
  Issue done when: `ClusterSecretStore vault` `Ready`.
