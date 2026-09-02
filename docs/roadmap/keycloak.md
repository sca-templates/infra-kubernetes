# Project: Implement Keycloak

Area: Security & Identity · Wave 50 · Environments: local→dev→qa→prod
Depends on: postgres-app/keycloak-db (#10) — its database; cert-manager (#1) for TLS.
Project done when: Keycloak pod `Running`; realm `sca` exists with a test client;
login/redirect works over TLS.

## Milestone M1 — Deploy

M1 done when: pod `Running`, app `Synced`/`Healthy`.

- [ ] Issue #13 · Deploy `bitnami/keycloak` (+ realm `sca`)
  Depends on: postgres-app/keycloak-db (#10), cert-manager (#1)
  - [ ] `infrastructure/keycloak/` values-base + overlays for 4 envs
        - [ ] envs/local, dev, qa, prod
        - Commits: `feat(keycloak): add chart reference and per-env overlays`
  - [ ] DB connection to `keycloak-db` (CNPq), not in-cluster H2
        Commits: `feat(keycloak): external database connection`
  - [ ] realm `sca` + test client + user
        Commits: `feat(keycloak): sca realm and test client`
  - [ ] smoke: login → redirect roundtrip over TLS
        Commits: `test(keycloak): login and redirect smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(keycloak): mark deployed`
  Issue done when: realm `sca` + TLS login works.

No natural further phases → issues stay under M1.
