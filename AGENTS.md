# infra-kubernetes — Platform Guide

GitOps source of truth for the `sca` infrastructure platform on Kubernetes.
ArgoCD reconciles this repository: **nothing is deployed by hand** — every
change lands through git. The Docker Compose sibling repositories
(`sca-templates/infra-*`) remain the local-dev counterpart only, outside this
repo.

## 1. What this repo is

- Single source of truth for the platform: components, environments, secret
  projections.
- ArgoCD app-of-apps: one root Application per environment renders an
  ApplicationSet that generates one Application per component.
- A **clean restart** of the previous `infra-kubernetes` (which churned in
  `fix` commits): one component per commit, a human-reviewed gate per phase,
  rollback over forward-fix.
- A **template**: it must be clonable standalone. Zero references to local
  paths outside the repo; sibling knowledge is always an external link.

**Knowledge base**: this guide is the rules of engagement; the file-accurate
documentation set lives in `docs/` (start at [docs/INDEX.md](docs/INDEX.md)).
From Phase 1 onward the docs are the **source of truth**: phase prompts read
them first, execute against their gates, and update `status.md` /
`architecture.md` as components land. Prefer the docs over recollection.

## 2. Environment model

| Environment | Profile | Sync policy | Purpose |
| --- | --- | --- | --- |
| `local` | 1 replica, full catalog, minimal resources | auto-sync + prune | Developer machine (kind) |
| `dev` | reduced HA | auto-sync + prune | Shared integration |
| `qa` | HA (3 replicas, PDBs, anti-affinity) | auto-sync, **no prune** | Pre-production validation |
| `prod` | full HA, real storage | **manual sync** | Production |

Sync policies follow ADR-003. Promotion is gated by the `promote-test`
([docs/workflow.md](docs/workflow.md)).

## 3. Component catalog

**17 components + ArgoCD.** Status column is the source of truth
(`planned (Phase N)` until the phase lands; `deployed` from then on). Chart
and image pins are set inside each phase and live under
`infrastructure/<component>/` + `envs/<env>/`.

| Component | Namespace | Upstream chart | Role | Provenance | Status |
| --- | --- | --- | --- | --- | --- |
| cert-manager | `cert-manager` | jetstack/cert-manager | In-cluster TLS issuers | — | planned (Phase 1) |
| Vault | `vault` | hashicorp/vault | Secrets SSOT (KV-v2 + k8s auth) | [infra-vault](https://github.com/sca-templates/infra-vault) | planned (Phase 2) |
| External Secrets | `external-secrets` | external-secrets/external-secrets | Projects Vault KV → native Secrets | — | planned (Phase 3) |
| linkerd-crds | `linkerd` | linkerd/linkerd-crds | Mesh CRDs | [infra-linkerd](https://github.com/sca-templates/infra-linkerd) | planned (Phase 4) |
| CloudNativePG | `cloudnative-pg` | cloudnative-pg/cloudnative-pg | PostgreSQL operator | — | planned (Phase 5) |
| Strimzi | `strimzi` | strimzi/strimzi-kafka-operator | Kafka operator (KRaft) | [infra-kafka](https://github.com/sca-templates/infra-kafka) | planned (Phase 6) |
| redis-operator | `data` | ot-container-kit/redis-operator | Redis operator | [infra-redis](https://github.com/sca-templates/infra-redis) | planned (Phase 7) |
| Kong | `kong` | kong/kong (DB-less) | Edge gateway, dedicated Application, no SSA | [infra-kong](https://github.com/sca-templates/infra-kong) | planned (Phase 8) |
| Linkerd control plane | `linkerd` | linkerd/linkerd2 (script) | mTLS identity, golden signals | [infra-linkerd](https://github.com/sca-templates/infra-linkerd) | planned (Phase 9) |
| postgres-app (+ keycloak-db) | `data` | CNPG `Cluster` CRs (raw) | App + Keycloak databases; local only | [infra-postgres](https://github.com/sca-templates/infra-postgres) | planned (Phase 10) |
| Kafka | `data` | `Kafka`/`KafkaNodePool` CRs | Event backbone, SCRAM | [infra-kafka](https://github.com/sca-templates/infra-kafka) | planned (Phase 11) |
| Redis | `data` | `Redis` CR | Cache | [infra-redis](https://github.com/sca-templates/infra-redis) | planned (Phase 12) |
| Keycloak | `keycloak` | bitnami/keycloak | OIDC IdP, realm `sca` | [infra-keycloak](https://github.com/sca-templates/infra-keycloak) | planned (Phase 13) |
| kube-prometheus-stack | `observability` | prometheus-community/kube-prometheus-stack | Metrics + Grafana + Alertmanager | [infra-prometheus](https://github.com/sca-templates/infra-prometheus) | planned (Phase 14) |
| Loki | `loki` | grafana/loki | Log aggregation | [infra-loki](https://github.com/sca-templates/infra-loki) | planned (Phase 15) |
| Alloy | `observability` | grafana/alloy | Ships pod logs to Loki | — | planned (Phase 15) |
| Tempo | `tempo` | grafana/tempo | Distributed tracing (OTLP) | [infra-tempo](https://github.com/sca-templates/infra-tempo) | planned (Phase 16) |
| MinIO | `minio` | minio/minio | S3 stand-in (local): Velero | — | planned (Phase 17) |
| Velero | `velero` | vmware-tanzu/velero | Cluster backup/restore | [infra-velero](https://github.com/sca-templates/infra-velero) | planned (Phase 18) |
| ArgoCD | `argocd` | argoproj/argo-cd (Makefile) | GitOps engine | — | **deployed** (Phase 0.0) |

**Intentional exclusions** (per the restart plan): no Consul in-cluster
(ADR-001; native DNS + Linkerd replace it), no Unleash, no
KafkaConnect/Debezium, no kafka-ui, no linkerd-viz in-cluster. No `latest`
tags; this repo builds nothing.

## 4. Dependency order (sync-waves)

ArgoCD `sync-wave` annotations, integers spaced ≥10 apart. Operators/CRDs
before CRs; Vault before ESO syncs; datastores before consumers.

| Wave | Content |
| --- | --- |
| -30 | Root Application per env |
| -20 | ApplicationSet, namespaces, cert-manager (+CRDs) |
| -10 | Pure operators/CRDs: external-secrets, linkerd-crds, cloudnative-pg, strimzi, redis-operator |
| 0 | Vault |
| 10 | Vault seeded by `bootstrap/seed-vault.sh` after pod `Running` (CI/manual, not an ArgoCD hook) |
| 20 | Kong |
| 30 | Linkerd control plane (deployed by script) |
| 40 | Datastores: postgres-app, keycloak-db (CNPG), kafka, redis CRs |
| 50 | Consumers: keycloak |
| 60 | Observability: kube-prometheus-stack, loki, alloy, tempo |
| 70 | MinIO (local only) |
| 80 | Velero |

The normative map with rationale lives in `docs/architecture.md`.

## 5. Image policy (strict)

Infrastructure uses **official upstream images pinned by version**. This repo
builds nothing. No floating tags, no `latest`, ever — enforced by the CI pin
guards ([docs/security.md](docs/security.md)).

## 6. Commands

| Command | What it does |
| --- | --- |
| `make prereqs` | Install pinned kubectl/helm/kind into `~/.local/bin` (idempotent) |
| `make cluster-up` | Create the local `kind` cluster from `bootstrap/kind-config.yaml` |
| `make cluster-down` | Delete the local `kind` cluster (keeps nothing) |
| `make bootstrap` | Install ArgoCD + apply the root Application for `$ENV` |
| `make status` | Cluster, ArgoCD apps and pod health overview |
| `make validate` | Static suite + live cluster checks |
| `make validate-static` | Static suite only: markdownlint, yamllint, YAML parse, `bash -n` |
| `make port-forward APP=<name>` | Reach a platform UI/API locally (argocd, vault, keycloak, grafana, prometheus, …) |
| `make clean` | Remove local state (`.env`, `.secrets/`, generated artifacts) |

The Makefile is a **thin wrapper**: after bootstrap, deployments happen
exclusively via `git push` → ArgoCD.

## 7. Conventions (strict)

- English only: content, commits, PR descriptions.
- Conventional commits: `feat(platform): …`, `feat(vault): …`,
  `docs(readme): …`.
- **One component = one commit = one PR = one review.** A blocked component
  rolls back; no `fix` chains, no ad-hoc `ignoreDifferences`/SSA patches.
- Changes land through PRs (initial population excepted, straight to `main`).
- **Never commit** `.env`, `.secrets/`, kubeconfigs, unseal keys, tokens,
  dumps. Vault is the secrets SSOT; `.secrets/` lives only on disk.
- Shared values changed must be mirrored across all `envs/<env>/<c>.yaml`.
- Respect sync-waves: a new component gets a wave ≥10 apart from its
  dependencies.
- From Phase 1, the commit that lands a component also updates
  `docs/architecture.md` (Status, deviations log) and `docs/status.md`
  (roadmap row). Docs are updated as components land.
- Consult the sca-docs notes below before touching topology, ports or networks.

## 8. Documentation to consult (always)

Fetch from the [sca-docs](https://github.com/sca-templates/sca-docs) vault
(raw URLs, no local checkout assumed):

- `00-ecosystem/platform-overview.md` — ecosystem vision
- `00-ecosystem/conventions.md` — naming, links, catalogs
- `06-decisions/adr-001` … `adr-007` — locked architecture decisions
  (ADR-001 no in-cluster Consul, ADR-003 sync policies)
- `04-infrastructure/<component>.md` — per-component canonical notes

Base URL: `https://raw.githubusercontent.com/sca-templates/sca-docs/main/<path>`

## 9. Troubleshooting quick refs

| Symptom | Probable cause | Fix |
| --- | --- | --- |
| ArgoCD app `OutOfSync` | Drift or failed sync-wave | `kubectl get application <name> -n argocd`; check `status.conditions`; sync manually if prod |
| ExternalSecret `SecretSyncedError` | Vault path missing or k8s-auth role wrong | Check `ClusterSecretStore vault` Ready; verify path under `secret/<service>/<env>`; re-run `bootstrap/seed-vault.sh` (local) |
| Pods CrashLoopBackOff after a wave bump | Dependency started before its datastore/operator | Re-check wave assignment; consumers must be ≥10 above their dependency |
| kind cluster OOM | Host RAM exhausted | Stop the Compose stack before bootstrapping; 1-replica local profile |
| `ImagePullBackOff` | Bad pin or unreachable registry | Verify the pinned tag exists upstream; check node images; never float `latest` |
| ESO wedge (local) | Old long-refresh pattern | Do not restart ESO by hand; short refresh (~5 min) prevents recurrence |

Full runbooks live in `docs/workflow.md`.
