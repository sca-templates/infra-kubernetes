# Project: Implement postgres-app (CNPG)

Area: Data · Wave 40 · Environments: local→dev→qa→prod (app DB + zitadel-db in all four)
Depends on: cloudnative-pg (#10) — operator must be present.
Project done when: `Cluster` `postgres-app` is `Ready` with its app schema and
`zitadel-db` is `Ready` (consumed by Zitadel, ADR-004). The former `keycloak-db`
cluster was removed in E4 and is kept below only as milestone history.

## Milestone M1 — Application database cluster

M1 done when: `Cluster postgres-app` `Ready` (1 replica local/dev, 3 qa/prod)
and `zitadel-db` `Ready` in all four environments.

- [x] Issue #15 · `Cluster` CRs `postgres-app` + `keycloak-db` (M1 issues #27 · #28)
  Depends on: cloudnative-pg (#10)
  - [x] `infrastructure/postgres-app/` raw `Cluster` CRs for 4 envs
        - [x] local/dev: 1 replica; qa/prod: 3 replicas
        - [x] PostgreSQL `18.4-standard-trixie` (official CNPG image; includes
              `pgaudit` and `pgvector`, and works with the Barman Cloud Plugin;
              no `latest`)
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
  fixed parameter. `pgaudit` is created through `postInitApplicationSQL` in
  every env with `pgaudit.log: "ddl, role"`.
- `app_migrator`, `app_rw`, `app_ro` and `vault_admin` are `DatabaseRole` CRs
  (wave 30) whose passwords come from Vault via ESO (wave 10); wave-40 Jobs
  wait for those roles to exist before applying schema grants to the already
  running clusters, and `local` is the only env without the `workload=database`
  selector. `requests` equal `limits` in all four envs so instance pods are
  `Guaranteed`; `local` uses 100m/256Mi to fit the single-node CPU budget while
  `dev`/`qa`/`prod` keep their larger profiles.
- `qa`/`prod` use `podAntiAffinityType: preferred` so the 3-instance profile
  remains schedulable on the single-node promote-test substrate.
- `postgres-app` is a dedicated raw `Application` per environment (not in the
  Helm `ApplicationSet`) because the CNPG `Cluster` is a CR, not a chart. The
  catalog preload resolves the CNPG image from the raw manifests too.
- The `system` CNPG images are deprecated and removed in operator 1.32. They
  were only needed by the retired native `barmanObjectStore` path; the Barman
  Cloud Plugin now supplies the `barman-cloud-*` binaries, so all clusters use
  `18.4-standard-trixie` and the security workflow rejects any `-system-` pin
  under `infrastructure/`.

No natural further phases → issues stay under M1.
