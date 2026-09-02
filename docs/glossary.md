# Glossary

Every term and component name used across this documentation, explained in one
place. Frequent component facts (charts, waves) are not repeated here — they
live in [architecture.md](architecture.md).

## Concepts

| Term | Meaning |
| --- | --- |
| **app-of-apps** | ArgoCD pattern: one root `Application` renders an `ApplicationSet` that generates one `Application` per component |
| **ARGO sync-wave** | Integer annotation ordering ArgoCD applies during sync; spaced ≥10 in this repo so dependencies apply first |
| **Bootstrap** | The one-time `make bootstrap`: installs ArgoCD and applies the env root `Application`; after it, nothing is deployed by hand |
| **chart** | A packaged Helm application (templates + values) |
| **CR** / **CRD** | Custom Resource / Custom Resource Definition; CRDs are installed by operators, CRs are the actual instances |
| **GitOps** | Git is the single source of truth; the cluster converges toward it |
| **Operator** | Controller + CRDs; reconciles the cluster toward a desired state (CNPG, Strimzi, redis-operator, cert-manager, ESO) |
| **promote-test** | Validating an env overlay (dev/qa/prod) on a local `kind` cluster before promotion ([workflow.md](workflow.md)) |
| **radar** | The alert/notification layer (PrometheusRules severity `info`) that flags prod sync windows ([observability-radar.md](observability-radar.md)) |
| **SSA** | Server-Side Apply, a sync strategy; deliberately **not** global in this repo (breaks Kong's flat CRDs) |
| **SSOT** | Single source of truth — the repo (GitOps) and Vault (secrets) |

## Components

| Name | One-line role |
| --- | --- |
| **cert-manager** | Issues in-cluster TLS certificates (issuers, `Certificate` CR). Phase 1 |
| **Vault** | Secrets SSOT: KV-v2 + kubernetes auth; HA raft. Phase 2 |
| **External Secrets Operator** | Projects Vault KV → native `Secret`s. Phase 3 |
| **Linkerd** | Service mesh: mTLS identity, golden signals. CRDs Phase 4, control plane Phase 9 |
| **CloudNativePG (CNPG)** | PostgreSQL operator (`Cluster` CR). Phase 5, `postgres-app`/`keycloak-db` Phase 10 |
| **Strimzi** | Kafka operator (KRaft); `Kafka` + `KafkaNodePool` CRs. Phases 6/11 |
| **redis-operator** | Redis operator (`Redis` CR). Phases 7/12 |
| **Kong** | API gateway (DB-less, dedicated `Application`, no SSA). Phase 8 |
| **Keycloak** | OIDC IdP (realm `sca`). Phase 13 |
| **kube-prometheus-stack** | Prometheus + Grafana + Alertmanager + the `ServiceMonitor`/`PrometheusRule` CRDs. Phase 14 |
| **Loki / Alloy / Tempo** | Log aggregation / pod-log shipping / distributed tracing (OTLP). Phases 15/16 |
| **MinIO** | S3-compatible object store, local-only (Velero, Loki, storage tests). Phase 17 |
| **Velero** | Cluster backup/restore to object storage. Phase 18 |

Phase numbers refer to the roadmap in [status.md](status.md).

## Environments

| Term | Meaning |
| --- | --- |
| **local** | Developer machine, `kind`, 1 replica, full catalog, auto+prune |
| **dev** | Shared integration, reduced HA, auto+prune |
| **qa** | Pre-production, HA (3 replicas, PDBs, anti-affinity), auto, **no prune** |
| **prod** | Production, full HA, real storage, **manual** sync |

## Repo vocabulary

| Term | Meaning |
| --- | --- |
| **`envs/<env>/`** | Per-environment overlays (one file per component) |
| **`infrastructure/<component>/`** | Per-component chart reference + shared values + CRs/manifests |
| **`argocd/apps-<env>.yaml`** | Per-env `ApplicationSet` generator — the component registry |
| **`argocd/root-app-<env>.yaml`** | Per-env root `Application` |
| **`{{GIT_REPO_URL}}`** | Placeholder in repoURL fields; substituted by `make bootstrap` from `GIT_REPO_URL` |
