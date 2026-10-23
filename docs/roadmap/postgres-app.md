# Project: Implement postgres-app (CNPG)

Area: Data · Wave 40 · Environments: local→dev→qa→prod (app DB + keycloak-db in all four)
Depends on: cloudnative-pg (#10) — operator must be present.
Project done when: `Cluster` `postgres-app` is `Ready` with its app schema;
`keycloak-db` cluster `Ready` (consumed by Keycloak #18).

## Milestone M1 — Application database cluster

M1 done when: `Cluster postgres-app` `Ready` (1 replica local/dev, 3 qa/prod)
and `keycloak-db` `Ready` in all four environments.

- [x] Issue #15 · `Cluster` CRs `postgres-app` + `keycloak-db` (M1 issues #27 · #28)
  Depends on: cloudnative-pg (#10)
  - [x] `infrastructure/postgres-app/` raw `Cluster` CRs for 4 envs
        - [x] local/dev: 1 replica; qa/prod: 3 replicas
        - [x] PostgreSQL `18.4-standard-trixie` (official CNPG image, pgvector
              in the `standard` flavor; no `latest`)
        - [x] credentials projected by ESO from `secret/postgres-app/<env>`
              and `secret/keycloak-db/<env>` (`kubernetes.io/basic-auth`)
        - Commits: `feat(db): add postgres-app cnpg deployment and smoke test`
  - [x] `keycloak-db` cluster CR (used by Keycloak #18)
        - DB + owner `keycloak`, storage 1/2/5/10 GiB
        Commits: `feat(db): add keycloak-db cluster and extend postgres smoke`
  - [x] smoke: pods `Running`, both clusters report `Ready`; a query through
        each projected user works; `postgres-app` carries `pgvector` +
        `pg_stat_statements` and `wal_level=logical`
        Covered in the two commits above
  - [x] docs: Work Log row + catalog Status → deployed
        Commits: `docs(postgres-app): mark deployed`
  Issue done when: both clusters report `Ready`.

Notes:

- `pg_stat_statements` is enabled with `pg_stat_statements.track: all`; CNPG
  then manages `shared_preload_libraries` and creates the extension itself.
  Setting the library directly in `spec.postgresql.parameters` is rejected as a
  fixed parameter.
- `qa`/`prod` use `podAntiAffinityType: preferred` so the 3-instance profile
  remains schedulable on the single-node promote-test substrate.
- `postgres-app` is a dedicated raw `Application` per environment (not in the
  Helm `ApplicationSet`) because the CNPG `Cluster` is a CR, not a chart. The
  catalog preload resolves the CNPG image from the raw manifests too.

No natural further phases → issues stay under M1.
