# Project: Implement postgres-app (CNPG)

Area: Data · Wave 40 · Environments: local→dev→qa→prod (app DB + keycloak-db; local only)
Depends on: cloudnative-pg (#5) — operator must be present.
Project done when: `Cluster` `postgres-app` is `Ready` with its app schema;
`keycloak-db` cluster `Ready` (consumed by Keycloak #13).

## Milestone M1 — Application database cluster

M1 done when: `Cluster postgres-app` `Ready` (3/3 for HA envs, 1 for local).

- [ ] Issue #10 · `Cluster` CR `postgres-app` (raw) + `keycloak-db`
  Depends on: cloudnative-pg (#5)
  - [ ] `infrastructure/postgres-app/` raw `Cluster` CRs for 4 envs
        - [ ] local/dev: 1 replica; qa/prod: 3 replicas
        - Commits: `feat(postgres-app): app cluster CR`
  - [ ] `keycloak-db` cluster CR (used by Keycloak #13)
        Commits: `feat(keycloak-db): database cluster CR`
  - [ ] smoke: pods `Running`, cluster reports `Ready`; simple query works
        Commits: `test(postgres-app): cluster ready smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(postgres-app): mark deployed`
  Issue done when: both clusters report `Ready`.

No natural further phases → issues stay under M1.
