# Platform Architecture

Reference for the `sca` platform on Kubernetes: layers, the component catalog,
sync-waves, namespaces, the secret flow and the environment model. This is a
**state document** — how the platform *is*. Nothing beyond ArgoCD is deployed
yet (Phase 0.1): every catalog entry is marked `planned` until its phase lands.
For how changes *flow* through the platform, see
[workflow.md](workflow.md); for what is done and what is next, see
[status.md](status.md).

## Overview

`infra-kubernetes` is the single source of truth for the platform. ArgoCD (in
each environment cluster) reconciles this repository via an app-of-apps
pattern per environment: one root `Application`
(`argocd/root-app-<env>.yaml`) renders one `ApplicationSet`
(`argocd/apps-<env>.yaml`) that generates one `Application` per component
from a list generator. There is **no global `ServerSideApply`**, Kong is a
dedicated `Application`, and `postgres-app` is a local raw `Application` (see
[Sync-wave map](#sync-wave-map) and the [Deviations log](#deviations-log)).
Nothing is deployed by hand after `make bootstrap`.

## Layers

```mermaid
graph TD
    subgraph Git["infra-kubernetes"]
        A["root-app-<env>.yaml"] --> B["ApplicationSet apps-<env>.yaml"]
    end
    subgraph ArgoCD["ArgoCD (per environment)"]
        B --> C[Security & Identity]
        B --> D[Edge & Mesh]
        B --> E[Data]
        B --> F[Observability]
        B --> G[Delivery & Resilience]
    end
    subgraph Security["Security & Identity"]
        C --> C1[cert-manager]
        C --> C2[Vault]
        C --> C3[External Secrets]
        C --> C4[Keycloak]
    end
    subgraph Edge["Edge & Mesh"]
        D --> D1[Kong]
        D --> D2[Linkerd control plane]
    end
    subgraph Data["Data"]
        E --> E1[CloudNativePG / postgres-app]
        E --> E2[Strimzi / Kafka]
        E --> E3[Redis]
    end
    subgraph Obs["Observability"]
        F --> F1[kube-prometheus-stack]
        F --> F2[Loki + Alloy]
        F --> F3[Tempo]
    end
    subgraph Delivery["Delivery & Resilience"]
        G --> G1[MinIO]
        G --> G2[Velero]
    end
```

Every box above is either an upstream Helm chart, a set of raw manifests, or
both. This repository builds no images.

## Component catalog

The catalog has **17 components**. Each row shows its intended namespace,
upstream chart, ArgoCD sync-wave and roadmap phase. Chart and image pins are
set per component when that phase lands (values live under
`infrastructure/<component>/` and `envs/<env>/` from Phase 1 on); nothing in
this table is deployed yet except ArgoCD itself.

| Component | Namespace | Upstream chart | Wave | Phase | Status |
| --- | --- | --- | --- | --- | --- |
| cert-manager | `cert-manager` | jetstack/cert-manager | -20 | 1 | planned (Phase 1) |
| vault | `vault` | hashicorp/vault | 0 | 2 | planned (Phase 2) |
| external-secrets | `external-secrets` | external-secrets/external-secrets | -10 | 3 | planned (Phase 3) |
| linkerd-crds | `linkerd` | linkerd/linkerd-crds | -10 | 4 | planned (Phase 4) |
| cloudnative-pg | `cloudnative-pg` | cloudnative-pg/cloudnative-pg | -10 | 5 | planned (Phase 5) |
| strimzi | `strimzi` | strimzi/strimzi-kafka-operator | -10 | 6 | planned (Phase 6) |
| redis-operator | `data` | ot-container-kit/redis-operator | -10 | 7 | planned (Phase 7) |
| kong | `kong` | kong/kong (DB-less) | 20 | 8 | planned (Phase 8) |
| linkerd control plane | `linkerd` | linkerd/linkerd2 (script) | 30 | 9 | planned (Phase 9) |
| postgres-app (+ keycloak-db) | `data` | CNPG `Cluster` CR (raw) | 40 | 10 | planned (Phase 10) |
| kafka (CR) | `data` | `Kafka` + `KafkaNodePool` CRs | 40 | 11 | planned (Phase 11) |
| redis (CR) | `data` | `Redis` CR | 40 | 12 | planned (Phase 12) |
| keycloak | `keycloak` | bitnami/keycloak | 50 | 13 | planned (Phase 13) |
| kube-prometheus-stack | `observability` | prometheus-community/kube-prometheus-stack | 60 | 14 | planned (Phase 14) |
| loki | `loki` | grafana/loki | 60 | 15 | planned (Phase 15) |
| alloy | `observability` | grafana/alloy | 60 | 15 | planned (Phase 15) |
| tempo | `tempo` | grafana/tempo | 60 | 16 | planned (Phase 16) |
| minio | `minio` | minio/minio | 70 | 17 | planned (Phase 17) |
| velero | `velero` | vmware-tanzu/velero | 80 | 18 | planned (Phase 18) |
| argocd | `argocd` | argoproj/argo-cd (Makefile bootstrap) | -30 | 0.0 | deployed — root app OutOfSync until the repo is live |

Notes:

- **Status column** is the source of truth for "is it live?". At Phase 0.1 only
  ArgoCD is deployed; every component is `planned (Phase N)`. The column is
  flipped to `deployed` inside the phase that lands the component, and
  `status.md` is updated in the same commit.
- `postgres-app` is a **local-only** raw `Application` (not in the
  `ApplicationSet` generator list) and also defines the `keycloak-db` CNPG
  cluster in `data` used by Keycloak in every environment. The Kafka and Redis
  **operators** (waves -10) are installed everywhere; their **custom resources**
  live in `data` at wave 40.
- `kong` is a dedicated `Application` per environment (not via the
  `ApplicationSet`): flat-schema CRDs break ArgoCD's structured-merge diff
  under `ServerSideApply=true`, so it runs DB-less with `installCRDs: false`
  and no SSA (see [Deviations log](#deviations-log)).
- The Linkerd control plane is **not** an ArgoCD app: it is deployed by a
  script (Phase 9) after cert-manager and linkerd-crds are up.
- `local` is the only environment running the full catalog including the
  observability stack, MinIO and Velero. See [Environment model](#environment-model).

## Sync-wave map

ArgoCD applies resources in `sync-wave` order (`argocd.argoproj.io/sync-wave`),
integers spaced ≥10 apart so dependencies are always satisfied. Wave -30 is
the root app; the ApplicationSet and cert-manager sit at -20; the operators
and CRDs at -10; then Vault and everything downstream.

```mermaid
graph LR
    subgraph W-30["-30"]
        A[Root Application per env]
    end
    subgraph W-20["-20"]
        B[ApplicationSet]
        C[cert-manager + CRDs]
    end
    subgraph W-10["-10 Operators/CRDs"]
        D[external-secrets]
        E[linkerd-crds]
        F[cloudnative-pg]
        G[strimzi]
        H[redis-operator]
    end
    subgraph W0["0"]
        I[Vault]
    end
    subgraph W10["10"]
        J[Vault seed - seed-vault.sh after pod Running]
    end
    subgraph W20["20"]
        K[Kong]
    end
    subgraph W30["30"]
        L[Linkerd control plane]
    end
    subgraph W40["40"]
        M[postgres-app / keycloak-db]
        N[Kafka CR]
        O[Redis CR]
    end
    subgraph W50["50"]
        P[Keycloak]
    end
    subgraph W60["60"]
        Q[kube-prometheus-stack]
        R[Loki]
        S[Tempo]
        T[Alloy]
    end
    subgraph W70["70"]
        U[MinIO]
    end
    subgraph W80["80"]
        V[Velero]
    end
    B --> C
    C --> D
    D --> I
    J --> K
    K --> L
    L --> M
    M --> P
    P --> Q
    U --> V
```

Key relationships:

- **ESO (wave -10) before Vault-secret consumers**: every `ExternalSecret`
  needs the `external-secrets` operator and the `vault` `ClusterSecretStore`.
- **Vault (wave 0) before Kong/Keycloak/datastores**, and `seed-vault.sh`
  (wave 10) runs after the Vault pod is `Running` — it is CI/manual, not an
  ArgoCD hook.
- **Kong (wave 20) before everything behind the gateway.**
- **kube-prometheus-stack (wave 60) before the radar** — the `ServiceMonitor`
  and `PrometheusRule` CRDs ship with this app. The radar design is in
  [observability-radar.md](observability-radar.md).

## Secret flow

```mermaid
graph LR
    A[Vault KV-v2] --> B[Vault Kubernetes auth]
    B --> C[External Secrets Operator]
    C --> D[K8s Secrets]
    D --> E[Application Pods]
    D --> F[CNPG Clusters / Kafka / Keycloak]
```

- Secrets are declared **once** in Vault at `secret/<service>/<env>` and
  projected to native Kubernetes `Secret`s by ESO. The cluster never stores
  the original secret; only the projected copy. `.secrets/` (disk only) is
  gitignored.
- ESO `refreshInterval` is short (~5 min) in `local` to avoid the
  ExternalSecret wedge that broke the previous attempt — no manual ESO
  restarts.

Full inventory and runbooks: [secrets.md](secrets.md).

## Namespace scheme

| Namespace | Purpose |
| --- | --- |
| `argocd` | ArgoCD control plane, root Applications, ApplicationSets |
| `cert-manager` | TLS certificate management |
| `vault` | Secrets SSOT |
| `external-secrets` | Secret projection from Vault |
| `linkerd` | Service mesh CRDs and control plane |
| `cloudnative-pg` | PostgreSQL operator |
| `strimzi` | Kafka operator |
| `kong` | API gateway |
| `data` | Datastores: postgres-app, keycloak-db, Kafka, Redis |
| `keycloak` | OIDC identity provider |
| `observability` | Metrics + Grafana + Alertmanager, Alloy log collection |
| `loki` | Log aggregation (named after the chart, unlike the observability ns) |
| `tempo` | Distributed tracing |
| `minio` | S3-compatible object storage (local only) |
| `velero` | Cluster backup/restore |

## Environment model

| Environment | Profile | Sync policy | Purpose |
| --- | --- | --- | --- |
| `local` | 1 replica, full catalog, minimal resources | auto-sync + prune | Developer machine (kind) |
| `dev` | reduced HA | auto-sync + prune | Shared integration |
| `qa` | HA (3 replicas, PDBs, anti-affinity) | auto-sync, **no prune** | Pre-production validation |
| `prod` | full HA, real storage | **manual sync** | Production |

Sync policies follow ADR-003. Promotion between environments is gated by the
`promote-test` (see [workflow.md](workflow.md)).

Per-component replica profile (intended values, materialized from Phase 1 on):

| Component | local | dev | qa | prod |
| --- | --- | --- | --- | --- |
| cert-manager | 1 | 2 | 3 | 3 |
| vault (HA raft) | 1 | 1 | 3 | 3 |
| external-secrets | 1 | 2 | 3 | 3 |
| cloudnative-pg | 1 | 1 | 2 | 2 |
| strimzi | 1 | 1 | 2 | 2 |
| redis | 1 | 1 | 2 | 3 |
| kong (gateway/controller) | 1/1 | 2/2 | 3/3 | 3/3 |
| keycloak | 1 | 2 | 3 | 3 |
| postgres-app | 1 | local-only | local-only | local-only |

- Vault `server.dataStorage.size`: `1Gi` default, `10Gi` (qa), `20Gi` (prod).
- Keycloak uses `podAntiAffinityPreset: hard` in `qa` and `prod`.
- `local` is the only environment that deploys the observability stack, MinIO
  and Velero, because it also plays the role of the demo/CI substrate.

## Deviations log

Repository-specific decisions, each with the reason. Appended by later phases
as each component lands; the log always explains *why*, never just *what*.

| Component | Deviation | Reason |
| --- | --- | --- |
| Root app (local) | `automated.enabled=false` applied live only (Phase 0.0); files keep auto + prune | The `GIT_REPO_URL` is a GitHub placeholder until the repo is published; disabling auto-sync live prevents the placeholder's legacy content from syncing. Reconciles to file state after publish |
| Kong | DB-less (`database: off`), `ingressController.installCRDs: false`, managed as a dedicated `Application`, no SSA | Kong ships flat-schema CRDs; structured-merge diff breaks under `ServerSideApply=true`, and `--include-crds` re-emits CRDs twice |
| postgres-app | Local raw `Application`, not in the `ApplicationSet` generator list | Only `local` runs the datastore; it must be applied without the env generator |
| Linkerd | Control plane deployed by script, not ArgoCD | Helm chart signature requirements; control plane needs cert-manager + linkerd-crds first |
| ESO | Short `refreshInterval` (~5 min) in local | Avoids the ExternalSecret wedge that wedged the previous attempt; restarts only ever manual after bootstrap |

## Change flow (summary)

Full detail in [workflow.md](workflow.md): a change lands via PR, is validated
by CI (static today; selective cluster smoke returns at Phase 1, profile
`local` — see [ci-cd.md](ci-cd.md)),
merges to `main`, and each environment's ArgoCD applies it according to its own
sync policy (`local`/`dev` auto, `qa` auto-no-prune, `prod` manual by a human).
