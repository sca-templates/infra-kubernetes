# Project: Implement Kong

Area: Edge & Mesh · Wave 20 · Environments: local→dev→qa→prod
Depends on: cert-manager (#1) — TLS for the gateway edge.
Project done when: Kong gateway serves a route with TLS via cert-manager; DB-less
config is in git; the dedicated Application has no SSA (`ServerSideApply`: off).

## Milestone M1 — Gateway deployment

M1 done when: pod `Running`, app `Synced`/`Healthy`.

- [ ] Issue #8 · Deploy `kong/kong` (DB-less, dedicated Application, no SSA)
  Depends on: cert-manager (#1)
  - [ ] `infrastructure/kong/` values-base + overlays for 4 envs
        - [ ] envs/local, dev, qa, prod
        - Commits: `feat(kong): add chart reference and per-env overlays`
  - [ ] dedicated Application with `syncOptions` SSA disabled
        Commits: `feat(kong): dedicated application without SSA`
  - [ ] DB-less config (declarative routes) in git
        Commits: `feat(kong): declarative db-less configuration`
  - [ ] smoke: Gateway receives a route + TLS certificate served
        Commits: `test(kong): route and tls smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(kong): mark deployed`
  Issue done when: gateway route works + TLS via cert-manager.

No natural further phases → issues stay under M1.
