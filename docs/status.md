# Status: Current State and Known Gaps

An honest picture of the platform today: what is deployed where, what is being
worked on, what is intentionally absent. Anything not listed here is either in
the component catalog ([architecture.md](architecture.md)) or does not exist.

## Current state

**Phase 0.1 — scaffold + knowledge base only.** Nothing beyond ArgoCD is
deployed. Phase 0.0 delivered the empty scaffold (Makefile, `bootstrap/`,
`argocd/` with `{{GIT_REPO_URL}}` placeholders, the four CI workflows, the
service template, this docs set) and brought the local `kind` cluster up with
ArgoCD. Phase 0.1 adds this knowledge base, which is **the source of truth**
for everything deployed in Phases 1–18 and beyond.

| Fact | Value |
| --- | --- |
| Repository | `infra-kubernetes` (local; published to GitHub before Phase 1 — a live `GIT_REPO_URL` is a Phase 1 gate) |
| Deployed components | ArgoCD only (bootstrap) |
| `platform-root-local` | present, `OutOfSync` (accepted — no live repo yet) |
| `platform-local` ApplicationSet | present, empty `elements: []` (0 generated apps) |
| Observability / smoke CI | not yet shipped (see [ci-cd.md](ci-cd.md)) |
| dev / qa / prod clusters | pending (provisioned by terraform/ansible, outside this repo) |

## Roadmap

The 18 phases, each with a human-reviewed functional gate. A component that
does not turn green **rolls back** — there are no `fix(...)` chains. Every
phase lands as one component, one commit, one review.

| Phase | Component | Functional gate |
| --- | --- | --- |
| 1 | cert-manager + `sca-ca` ClusterIssuer | test Certificate Ready |
| 2 | Vault (raft) | pod Ready, `vault status` initialized + unsealed, TLS via cert-manager, idempotent seed |
| 3 | external-secrets + ClusterSecretStore | smoke ExternalSecret → `SecretSynced` |
| 4 | linkerd-crds | CRDs present, app Healthy |
| 5 | cloudnative-pg | `Cluster` CRD accepted |
| 6 | strimzi | `Kafka`/`KafkaNodePool` CRDs |
| 7 | redis-operator | `Redis` CRD |
| 8 | Kong (dedicated app) | echo service via NodePort 30080, admin Healthy |
| 9 | Linkerd control plane (script) | mTLS identity up |
| 10 | postgres-app + keycloak-db | clusters Ready, `psql SELECT 1` |
| 11 | Kafka CR + SCRAM | create topic + produce/consume smoke |
| 12 | Redis CR | `SET`/`GET` |
| 13 | Keycloak | admin API login, valid RS256 JWT |
| 14 | kube-prometheus-stack | Prometheus + Grafana up, targets, radar rules |
| 15 | Loki + Alloy | logs queryable |
| 16 | Tempo | OTLP up, trace smoke |
| 17 | MinIO (local-only, wave 70) | health endpoint OK |
| 18 | Velero (wave 80) | install + schedule + backup/restore of a small namespace |

### Per-component Definition of Done (local)

- Component `Synced` + `Healthy` in ArgoCD.
- Pods `Running`, no `CrashLoopBackOff`/`ImagePullBackOff` after 2+ min stable.
- `ExternalSecret` → `SecretSynced` where applicable.
- One functional smoke (the table above).
- `make status` shows no new `Degraded`.
- Single commit, human-reviewed.

## Known accepted limitations

| # | Limitation | Current behavior | To close |
| --- | --- | --- | --- |
| 1 | **Root app OutOfSync** | `platform-root-local` shows `OutOfSync`; auto-sync disabled live because the `GIT_REPO_URL` placeholder is a public repo with legacy content | Publish this repo, swap `GIT_REPO_URL`, re-enable file-state (auto + prune) |
| 2 | **Cluster smoke CI absent** | `pr-cluster.yml` is deliberately not shipped yet | Rebuilt from scratch in later phases: selective smoke of the touched component, no trim hacks, no self-heal disabling |
| 3 | **dev / qa / prod clusters pending** | Not provisioned (terraform/ansible outside this repo) | Provision per env; promote via `promote-test` (see [workflow.md](workflow.md)) |
| 4 | **Nothing seeded in Vault** | Vault seed script ships (`bootstrap/seed-vault.sh`) but is never run — no Vault yet | Runs at Phase 2; short ESO `refreshInterval` in local prevents the previous wedge |

## Intentional exclusions

- **No Unleash, no KafkaConnect/Debezium, no kafka-ui, no linkerd-viz
  in-cluster.** They are deliberate scope cuts of the restart plan.
- **No Consul and no Consul-k8s in-cluster** (ADR-001): native Kubernetes DNS +
  Linkerd replace it.
- **No `latest` tags, no image builds**: infrastructure pins upstream
  releases; this repo builds nothing.

## Read this doc

- Before any change, check the [roadmap](#roadmap) and the [deviations
  log](architecture.md#deviations-log): they are the normative record.
- `local` is the demo/CI substrate; treat everything it runs as the minimal
  but *complete* platform, not as a reduced copy.
