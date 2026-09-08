# Project: Implement Vault

Area: Security & Identity · Wave 0 · Environments: local→dev→qa→prod
Depends on: cert-manager (#1)
Project done when: pod `Ready`; `vault status` initialized + unsealed; TLS via
cert-manager; idempotent seed; ESO consumes (integration with #3).

> **Status: deployed (Phase 2)** on `local` as an HA raft trio with TLS via a
> cert-manager leaf, an idempotent HA-aware seed, and a green smoke
> ([status](../status.md), [work log](../roadmap.md#work-log-global-reverse-chronological)).
> ESO integration (#2-3) lands with Phase 3.

## Milestone M1 — Operator bootstrap

M1 done when: chart deployed, pod `Running`, no `CrashLoopBackOff`.

- [x] Issue #2-1 · Deploy `hashicorp/vault` (raft/HA)
  Depends on: —
  - [x] `infrastructure/vault/` values-base + overlays for 4 envs
        - [x] envs/local, dev, qa, prod
        - Commits: `feat(vault): add chart reference and per-env overlays`
  - [x] registry appset element (wave 0)
        Commits: `feat(vault): register in apps appset (wave 0)`
  - [x] raft HA storage: base `server.ha.replicas: 3`, overridden per env —
        **local/qa/prod = 3 (HA trio), dev = 1**; local intentionally keeps HA
        so the local/smoke path exercises quorum + leader redirect like qa/prod
        Commits: `feat(vault): configure raft HA storage`
  Issue done when: app `Synced`/`Healthy` + pod `Running`.

## Milestone M2 — Seed + integration

M2 done when: unsealed; ESO consumes; TLS ok.

- [x] Issue #2-2 · Initialize + unseal (idempotent)
  - [x] unseal keys → `.secrets/` (never git)
        Commits: —
  - [x] `bootstrap/seed-vault.sh` idempotent (HA-aware: init on one node,
        unseal all peers, write via `vault-active`)
        Commits: `feat(vault): idempotent seed script` + HA-aware fixes in 669c848/d56dce1/9a03e33
  Issue done when: `vault status` → initialized=true, sealed=false.
  Verified by: `make smoke COMPONENT=vault`.

- [ ] Issue #2-3 · Kubernetes auth + `ClusterSecretStore` (ESO integration)
  - [ ] ClusterRole / k8s-auth role (seed already configures the role, but the
        `ClusterSecretStore` + `ExternalSecret`s land with the ESO deployment in
        Phase 3)
        Commits: `feat(vault): k8s auth role for ESO`
  - [ ] seed KV v2 path under `secret/<service>/<env>`
        Commits: `feat(vault): seed KV v2 secrets layout`
  Issue done when: `ClusterSecretStore vault` `Ready`.
