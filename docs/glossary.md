# Glossary

Every term and component name used across this documentation, explained in one
place. Frequent component facts (charts, waves) are not repeated here — they
live in [architecture.md](architecture.md).

## Concepts

| Term               | Meaning                                                                                                                                        |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| **app-of-apps**    | ArgoCD pattern: one root `Application` renders an `ApplicationSet` that generates one `Application` per component                              |
| **ARGO sync-wave** | Integer annotation ordering ArgoCD applies during sync; spaced ≥10 in this repo so dependencies apply first                                    |
| **Bootstrap**      | The one-time `make bootstrap`: installs ArgoCD and applies the env root `Application`; after it, nothing is deployed by hand                   |
| **chart**          | A packaged Helm application (templates + values)                                                                                               |
| **CR** / **CRD**   | Custom Resource / Custom Resource Definition; CRDs are installed by operators, CRs are the actual instances                                    |
| **GitOps**         | Git is the single source of truth; the cluster converges toward it                                                                             |
| **JetStream**      | NATS persistence layer (streams/consumers) enabled on the server and reconciled through NACK                                                   |
| **Operator**       | Controller + CRDs; reconciles the cluster toward a desired state (CNPG, redis-operator, cert-manager, ESO, NACK)                            |
| **promote-test**   | Validating an env overlay (dev/qa/prod) on a local (Floci emulated EKS) cluster before promotion ([workflow.md](workflow.md))                 |
| **radar**          | The alert/notification layer (PrometheusRules severity `info`) that flags prod sync windows ([observability-radar.md](observability-radar.md)) |
| **SSA**            | Server-Side Apply, a sync strategy; deliberately **not** global in this repo (breaks Kong's flat CRDs)                                         |
| **SSOT**           | Single source of truth — the repo (GitOps) and Vault (secrets)                                                                                 |

## Components

| Name                          | One-line role                                                                              |
| ----------------------------- | ------------------------------------------------------------------------------------------ |
| **cert-manager**              | Issues in-cluster TLS certificates (issuers, `Certificate` CR). Phase 1 (deployed) |
| **Vault**                     | Secrets SSOT: KV-v2 + kubernetes auth; HA raft. Phase 2 (deployed) |
| **External Secrets Operator** | Projects Vault KV → native `Secret`s. Phase 3 (deployed) |
| **CloudNativePG (CNPG)**      | PostgreSQL operator (`Cluster` CR). Phase 5, `postgres-app`/`keycloak-db` Phase 10         |
| **NATS JetStream**            | Event backbone (ADR-005); idle tier (no `Stream`/`Consumer` CRs), optional per env. NATS migration C1–C4; see [messaging.md](messaging.md) |
| **NACK**                      | NATS Controller for Kubernetes: installs the `Stream`/`Consumer` CRDs and reconciles them. NATS migration C1–C4; see [messaging.md](messaging.md) |
| **redis-operator**            | Redis operator (`Redis` CR). Phases 7/12                                                   |
| **Kong**                      | API gateway (DB-less, dedicated `Application`, no SSA). Phase 8                            |
| **Keycloak**                  | OIDC IdP (realm `sca`). Phase 13; being replaced per [ADR-004](adr/adr-004-keycloak-to-zitadel.md) |
| **Zitadel**                   | OIDC IdP replacing Keycloak; internal h2c with `zitadel-db` and a Kong/TLS edge, service cutover tracked in E3 |
| **kube-prometheus-stack**     | Prometheus + Grafana + Alertmanager + the `ServiceMonitor`/`PrometheusRule` CRDs. Phase 14 |
| **Loki / Alloy / Tempo**      | Log aggregation / pod-log shipping / distributed tracing (OTLP). Phases 15/16              |
| **Floci S3**                  | Local S3 emulator in the cloud/EKS tooling; Velero's local backup backend                   |
| **Velero**                    | Cluster backup/restore to object storage. Phase 18                                         |

Phase numbers refer to the roadmap in [roadmap.md](roadmap.md).

## Environments

| Term      | Meaning                                                                  |
| --------- | ------------------------------------------------------------------------ |
| **local** | Developer machine, Floci emulated EKS, 1 replica, full catalog, auto+prune |
| **dev**   | Shared integration, reduced HA, auto+prune                               |
| **qa**    | Pre-production, HA (3 replicas, PDBs, anti-affinity), auto, **no prune** |
| **prod**  | Production, full HA, real storage, **manual** sync                       |

## Repo vocabulary

| Term                              | Meaning                                                                            |
| --------------------------------- | ---------------------------------------------------------------------------------- |
| **`envs/<env>/`**                 | Per-environment overlays (one file per component)                                  |
| **`infrastructure/<component>/`** | Per-component chart reference + shared values + CRs/manifests                      |
| **`argocd/apps-<env>.yaml`**      | Per-env `ApplicationSet` generator — the platform component registry        |
| **`argocd/messaging-<env>.yaml`** | Optional `ApplicationSet` (git files generator) for NATS/NACK; the descriptors under `argocd/messaging/<env>/` toggle the messaging mode |
| **messaging contract**            | Vault KV-v2 `secret/messaging/<env>` (`mode` + `nats_url` or SNS/SQS coordinates) projected by each consumer through ESO |
| **`argocd/services-<env>.yaml`**  | Per-env `ApplicationSet` for services (app-repo-as-source); dev/qa/prod only, never `local`. dev/qa elements track `main` (synced by the service's `promote` workflow); prod elements carry a `version` tag pin (`chore(services)` bump = the deploy go/no-go) |
| **`promote` workflow**           | Per-service `workflow_dispatch` (wraps `shared-service-promote.yml`) that picks a branch/commit and syncs `<service>-dev` / `<service>-qa` via the ArgoCD API — replaces the retired `deploy/dev` · `deploy/qa` refs |
| **`argocd/root-app-<env>.yaml`**  | Per-env root `Application` (owns only the services registry; `dev`/`qa`/`prod` only — `local` has none) |
| **`{{GIT_REPO_URL}}`**            | Placeholder in `repoURL`/`targetRevision` fields of `argocd/apps-<env>.yaml`, `argocd/messaging-<env>.yaml`, the dedicated apps and the root app. `make bootstrap` substitutes them host-side (the `sed` seam) when it seeds the platform/messaging `ApplicationSet`s, the dedicated apps and the root app — the values used are the ref under test (the PR head in CI, `main` otherwise) |
