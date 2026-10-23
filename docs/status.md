# Status: Current State and Known Gaps

An honest picture of the platform today: what is deployed where, what is being
worked on, what is intentionally absent. Anything not listed here is either in
the component catalog ([architecture.md](architecture.md)) or does not exist.

The **delivery plan** (the 18 phases, their gates and the Work Log) now lives
in [roadmap.md](roadmap.md) and is tracked on the GitHub Projects board,
Milestones and Issues.

## Current state

**Phase 11 — Kafka deployed.** Phase 0 delivered the scaffold
(Makefile, `bootstrap/`, `argocd/` with the app-of-apps pattern, the CI
workflows, the service template, this docs set) and brought the local Floci
emulated EKS cluster up with ArgoCD. **Phase 1** lands cert-manager on the `local` profile
(fully-local: ArgoCD reconciles an in-cluster git serve instead of GitHub) and
ships the cluster smoke. **Phase 2** lands Vault — the secrets SSOT — as an HA
raft trio with TLS via a cert-manager leaf, an idempotent HA-aware seed, and a
green smoke. **Phase 3** lands External Secrets Operator: it projects Vault KV
into native Kubernetes `Secret`s through the `ClusterSecretStore vault`
(k8s-auth, TLS via the `vault-tls` leaf) with a short ~5 min refresh, and ships
a smoke proving a projected secret reaches `SecretSynced`. **Phase 4** lands
linkerd-crds — the service-mesh CRDs (`linkerd.io` + `policy.linkerd.io`, plus
the chart-default gateway `HTTPRoute`) in the `linkerd` namespace — a CRD-only
Application with no workloads; it is the base the Linkerd control plane
(Phase 9, wave 30) installs against. **Phase 5** lands CloudNativePG — the
PostgreSQL operator — at wave -10 in the `cloudnative-pg` namespace: chart
pinned 0.29.0 (operator 1.30.0), cluster-wide watch (`config.clusterWide`) so
the datastores can run in `data` at Phase 10, monitoring off until Phase 14,
with the 11 `postgresql.cnpg.io` CRDs all `Established`. **Phase 6** lands
Strimzi — the Kafka operator — at wave -10 in the `strimzi` namespace: chart
pinned 1.2.0 (operator 1.2.0, `quay.io/strimzi/operator`), watching every
namespace (`watchAnyNamespace`) so the Kafka datastores can run in `data` at
Phase 11, with the 10 `kafka.strimzi.io` / `core.strimzi.io` CRDs all
`Established`. **Phase 7** lands redis-operator — the Redis operator — at wave
-10 in the `data` namespace (shared with the datastores it will manage, unlike
the dedicated `strimzi` / `cloudnative-pg` namespaces): chart pinned 0.26.1
(operator 0.26.0, `quay.io/opstree/redis-operator`), cluster-wide watch
(`watchNamespace: ""` renders no `WATCH_NAMESPACE`) so the Redis datastores can
run in `data` at Phase 12, webhook off, no PDB, with the 4
`redis.redis.opstreelabs.in` CRDs all `Established`. Its smoke goes one step
further than the other operators: a throwaway `Redis` CR in a scratch namespace
must produce a Ready StatefulSet and answer `PING` → `PONG`, which is the
honest proof that the CR is honored (the `Redis` CRD declares an empty status
object, so no condition can be asserted). The Kafka custom resources land at
Phase 11 (below); the `Redis` CR at Phase 12. **Phase 8** lands Kong — the
edge gateway — as a **dedicated `Application` per environment (`kong-<env>`)** at
wave 20 in the `kong` namespace, deliberately *outside* the `ApplicationSet`:
chart pinned 3.4.1 (`kong/kong`), gateway `kong:3.9.4` plus the bundled
Kubernetes Ingress Controller (`kubernetes-ingress-controller:3.5.5`), DB-less
(`env.database: off`) with `installCRDs: false` (ArgoCD applies the chart's
`crds/` bundle) and, critically, **no `ServerSideApply`** — the appset's SSA
breaks the structured-merge diff on Kong's flat-schema `configuration.konghq.com`
CRDs, which is why the gateway is the one catalog component with a dedicated app
per env. Routing is declarative in git (`infrastructure/kong/manifests/`: an
`Ingress` on `ingressClassName: kong` plus a `request-termination` `KongPlugin`)
and the proxy serves TLS from a cert-manager leaf (`kong-proxy` /
`kong-proxy-cert` off the `sca-ca` ClusterIssuer). See
[ci-cd.md](ci-cd.md) for the smoke design. **Phase 9** lands the Linkerd
control plane as another **dedicated `Application` per environment**
(`linkerd-<env>`) at wave 30, with in-cluster identity PKI (cert-manager-issued
issuer anchored by the committed mesh root) and a data-plane end-to-end smoke;
no `linkerd-viz` (headless mesh). **Phase 10** lands the PostgreSQL
datastores: two CNPG `Cluster`s in `data` at wave 40 across **all four**
environments — `postgres-app` (`app`/`app`) and `keycloak-db`
(`keycloak`/`keycloak`) on official
`ghcr.io/cloudnative-pg/postgresql:18.4-standard-trixie`. They are raw CRs, so
they ship through a **dedicated `Application` per environment**
(`argocd/postgres-app-<env>.yaml`, `directory.include: "*-<env>.yaml"`) rather
than the Helm `ApplicationSet`; `local`/`dev` run 1 instance, `qa`/`prod` run 3
with `preferred` anti-affinity (schedulable on the single-node promote
substrate). ESO projects the bootstrap credentials from
`secret/postgres-app/<env>` and `secret/keycloak-db/<env>`.
`postgres-app` carries `pgvector` + `pg_stat_statements` (`pg_stat_statements.track:
all`; CNPG manages `shared_preload_libraries`) and `wal_level=logical`;
`keycloak-db` is ready for Phase 13. The catalog preload resolves the CNPG
image from the raw manifests, and `make smoke COMPONENT=postgres-app` validates
both clusters, both projected users, the extensions and logical WAL.
**Phase 11** lands the event backbone: a KRaft `Kafka` + `KafkaNodePool`
(1 dual-role node local/dev, 3 qa/prod) and a `KafkaUser scram-admin` in `data`
at wave 40, across **all four** environments. Kafka is pinned at `4.2.0`
(`quay.io/strimzi/kafka:1.2.0-kafka-4.2.0`); the internal listener `9092` is
TLS + SCRAM-SHA-512 with simple authorization and `scram-admin` as superUser.
The SCRAM password is projected by ESO from `secret/kafka/<env>` into the
`kafka-scram-admin` Secret and consumed by the User Operator through
`KafkaUser.spec.authentication.password.valueFrom`, so Vault stays the source of
truth. Like postgres-app, the CRs ship through a **dedicated `Application` per
environment** (`argocd/kafka-<env>.yaml`, `directory.include: "*-<env>.yaml"`)
rather than the Helm `ApplicationSet`; `local`/`dev` run one node with 1/2 GiB
storage and RF/minISR `1/1`, `qa`/`prod` run three with 10/20 GiB, RF/minISR
`3/2` and `preferred` anti-affinity. `make smoke COMPONENT=kafka` waits for the
projected credentials, Kafka, KafkaUser and brokers, then creates a topic and
produces/consumes one record over SASL_SSL/SCRAM.

| Fact | Value |
| --- | --- |
| Repository | `infra-kubernetes` (local, fully-local git serve; published to GitHub before promotion) |
| Deployed components | ArgoCD (bootstrap), cert-manager (Phase 1), Vault (Phase 2), external-secrets (Phase 3), linkerd-crds (Phase 4), cloudnative-pg (Phase 5), strimzi (Phase 6), redis-operator (Phase 7), Kong (Phase 8), Linkerd control plane (Phase 9), postgres-app/keycloak-db (Phase 10), Kafka (Phase 11) |
| `platform-root-local` | not used — `local` runs no services, so there is no root Application; `make bootstrap ENV=local` seeds the catalog wiring (`apps-local` + `kong-local` + `linkerd-local` + `postgres-app-local` + `kafka-local`) host-side |
| `platform-local` ApplicationSet | present, seven elements (`cert-manager` wave -20, `external-secrets` + `linkerd-crds` + `cloudnative-pg` + `strimzi` + `redis-operator` wave -10, `vault` wave 0) |
| cert-manager app | `cert-manager-local` `Synced` + `Healthy`; `sca-ca` ClusterIssuer `Ready`; leaf Certificate smoke green |
| vault app | `vault-local` `Synced` + `Healthy`; HA raft trio, TLS via `vault-tls` leaf; `make smoke COMPONENT=vault` → initialized=true sealed=false; seed idempotent and HA-aware |
| external-secrets app | `external-secrets-local` `Synced` + `Healthy`; `ClusterSecretStore vault` Ready (k8s-auth `external-secrets`, TLS via `vault-tls`); short `refreshInterval` (5m); `make smoke COMPONENT=external-secrets` → throwaway ExternalSecret `SecretSynced` + data verified |
| linkerd-crds app | `linkerd-crds-local` `Synced`, namespace `linkerd` present, CRD-only app (no workloads); `servers`/`serverauthorizations`/`serviceprofiles` + policy group all `Established`; `make smoke COMPONENT=linkerd-crds` green |
| cloudnative-pg app | `cloudnative-pg-local` `Synced` + `Healthy`; operator Deployment `cloudnative-pg` Ready (chart 0.29.0 / operator 1.30.0); 11 `postgresql.cnpg.io` CRDs present + `Established`; `make smoke COMPONENT=cloudnative-pg` green |
| strimzi app | `strimzi-local` `Synced` + `Healthy`; operator Deployment `strimzi-cluster-operator` Ready (chart 1.2.0 / operator 1.2.0); watches all namespaces (`STRIMZI_NAMESPACE=*`); 10 `kafka.strimzi.io` + `core.strimzi.io` CRDs present + `Established`; `make smoke COMPONENT=strimzi` green |
| redis-operator app | `redis-operator-local` `Synced` + `Healthy` in namespace `data`; operator Deployment `redis-operator` Ready (chart 0.26.1 / operator 0.26.0); watches all namespaces (no `WATCH_NAMESPACE` env); 4 `redis.redis.opstreelabs.in` CRDs present + `Established`; `make smoke COMPONENT=redis-operator` → throwaway `Redis` CR honored (StatefulSet ready + `PING` → `PONG`) |
| kong app | `kong-local` `Synced` + `Healthy` in namespace `kong` (dedicated Application, **no SSA**); chart 3.4.1, gateway Deployment `kong` Ready (containers `ingress-controller` KIC 3.5.5 + `proxy` kong 3.9.4), DB-less (`KONG_DATABASE=off`); IngressClass `kong`; `configuration.konghq.com` CRDs `Established`; `Certificate/kong-proxy` Ready (leaf off `sca-ca`); declarative `Ingress kong-demo` + `KongPlugin demo-termination`; `make smoke COMPONENT=kong` → `GET https://kong.local/demo` → 200 |
| linkerd app | `linkerd-local` `Synced` + `Healthy` (dedicated Application); chart `linkerd/linkerd-control-plane` 1.16.11 (`stable-2.14.10`); control-plane Deployments `linkerd-identity`/`linkerd-destination`/`linkerd-proxy-injector` Ready; identity PKI in-cluster (ConfigMap `linkerd-identity-trust-roots` + cert-manager-issued Secret `linkerd-identity-issuer`, chain to `root.linkerd.cluster.local` verified); 3 admission webhooks wired; `make smoke COMPONENT=linkerd` green, including **data plane end-to-end**: preflight of the control-plane identity-leaf TTL, an injected `nginx-unprivileged`+`curl` workload (both pods carry `linkerd-proxy`), HTTP 200 through the mesh, live identity leaves and inbound+outbound success metrics; `local` raises `identity.issuer.issuanceLifetime` to `168h0m0s` (emulator clock skew; dev/qa/prod keep 24h) |
| postgres-app app | `postgres-app-local` `Synced` + `Healthy` (dedicated Application, raw CRs); CNPG `Cluster postgres-app` Ready (1 instance local; image `18.4-standard-trixie`), `keycloak-db` Ready (1 instance local); ESO `postgres-app-credentials` + `keycloak-db-credentials` `SecretSynced`; `pg_stat_statements` + `vector` + `wal_level=logical` verified through `app@app`; `make smoke COMPONENT=postgres-app` green |
| kafka app | `kafka-local` `Synced` + `Healthy` (dedicated Application, raw CRs); Strimzi `Kafka/kafka` Ready (Kafka `4.2.0`), `KafkaNodePool/kafka` 1 dual-role node local; `KafkaUser/scram-admin` Ready; ESO `kafka-scram-admin` `SecretSynced` from `secret/kafka/local`; internal listener TLS + SCRAM-SHA-512; `make smoke COMPONENT=kafka` → topic create + produce/consume green |
| git-local-serve | in-cluster git daemon (`git://<node>:9418/sca-infra.git`) `Ready` |
| Observability / smoke CI | cluster smoke `pr-cluster.yml` **shipped** (Phase 1): selective on PRs as the **required `Smoke` check** on `main` + manual `workflow_dispatch`; no `push` smoke. Multi-component PRs smoke every touched component in one run (one boot/cloud/teardown); changes to the smoke framework (`bootstrap/smoke-*`, `argocd/**`, `Makefile`) resolve to `cert-manager` so the machinery is self-validated; the pinned toolchain is cached (`actions/cache`, keyed on `versions.sh`) (see [ci-cd.md](ci-cd.md)) |
| Cloud integration smoke | every smoke run also proves the cluster reaches the local cloud emulator (Floci): `make cloud-up` / `make smoke COMPONENT=cloud` green — bucket created and object round-tripped from an in-cluster Job; on by default, `--no-cloud` / `SMOKE_CLOUD=0` opts out. **Dev/CI tooling, not a platform component** (see [ci-cd.md](ci-cd.md)) |
| EKS substrate smoke | the required `Smoke` job boots the **full platform** on Floci's emulated **EKS** (real single-node k3s + ECR), the platform's only cluster substrate: `make eks-up` → `make bootstrap ENV=local` → Vault seeded before the health gate → every `<name>-local` Application `Synced`/`Healthy` → `make smoke COMPONENT=eks` green (ECR push + in-cluster pull round-trip via the node registry mirror) → endpoint smoke. Proves EKS integration (IAM kubeconfig) + the ECR image path. **Dev/CI tooling, not a platform component** (see [ci-cd.md](ci-cd.md)) |
| Security CI | checkov **baseline gate** active (Phase 1): `.github/checkov-baseline.json` documents the local-git-server pod findings; new IaC findings fail the PR; re-evaluated at Phase 18 (see [security.md](security.md)) |
| Release automation | **path-scoped** triggers active (see [versioning.md](versioning.md)): only `feat`/`fix` commits touching the platform surface open release PRs (`exclude-paths` in `.release-please-config.json`); release-please runs on `push: main` only via the shared `shared-release-flow.yml` wrapper; tag signing runs when a release is created (manual dispatch re-sign removed) |
| Release promotion | tags are cut automatically and the release goes out as a **full release held off `latest`**; `release-publish.yml` (manual) is the only step that moves the `latest` pointer, on a human go/no-go (see [versioning.md](versioning.md)) |
| dev / qa / prod clusters | pending (provisioned by terraform/ansible, outside this repo) |

## Known accepted limitations

| # | Limitation | Current behavior | To close |
| --- | --- | --- | --- |
| 1 | **Fully-local git serve (dev, not GitHub)** | Local **dev** ArgoCD can reconcile an in-cluster git serve (`git://<node>:9418`) instead of GitHub: `make local-git-up` mirrors this repo's HEAD verbatim onto the serve (`bootstrap/render-served-apps.sh`), while `make bootstrap` seeds the ArgoCD wiring (`argocd/apps-local.yaml`, `argocd/kong-local.yaml`) host-side with the placeholders resolved. The CI cluster smoke does **not** use the serve — it seeds the wiring host-side via `make bootstrap` | Publish the repo and swap `GIT_REPO_URL` back to GitHub to exercise the real source-of-truth path; the git serve stays dev-only tooling |
| 2 | **dev / qa / prod clusters pending** | Not provisioned (terraform/ansible outside this repo) | Provision per env; promote via `promote-test` (see [workflow.md](workflow.md)) |
| 3 | **OpenSSF Best Practices badge — silver blocked** | All silver criteria are met except `contributors_unassociated` and `bus_factor` (≥2): the project has a single maintainer (`CODEOWNERS` = `@Santiago1010`) | Achieved once a second **unassociated** contributor joins and is reflected in `CODEOWNERS` + `.github/GOVERNANCE.md`; passing badge is already achievable (see [.github/GOVERNANCE.md](../.github/GOVERNANCE.md), [docs/ci-cd.md](ci-cd.md)) |
| 4 | **OpenSSF Best Practices badge — gold blocked** | Beyond the silver gaps, gold requires `two_person_review` (≥50% of changes reviewed by someone other than the author), which is unrealisable while there is a single maintainer; all other gold criteria are Met or N/A (see [.github/SECURITY.md](../.github/SECURITY.md) security review, SPDX + copyright headers per source file) | Unblocked together with silver once a second, **unassociated** reviewer/maintainer exists; `two_person_review` then requires an explicit second reviewer on gold PRs |

## Intentional exclusions

- **No Unleash, no KafkaConnect/Debezium, no kafka-ui, no linkerd-viz
  in-cluster.** They are deliberate scope cuts of the restart plan.
- **No Consul and no Consul-k8s in-cluster** (ADR-001): native Kubernetes DNS +
  Linkerd replace it.
- **No `latest` tags, no image builds**: infrastructure pins upstream
  releases; this repo builds nothing.
- **No cloud in-cluster.** The cloud emulator (Floci) is smoke/CI tooling
  ([ci-cd.md](ci-cd.md)): it runs on the runner and is published to a scratch
  namespace for the duration of a smoke run — it is never part of the platform
  catalog, and no real cloud account, IAM or per-cloud configuration is used.
  The same holds for its **EKS substrate** (`eks-emulator.sh`): the emulated EKS
  cluster and ECR registry *are* the local cluster substrate for a smoke run, are
  never members of the platform catalog, and the IAM key it mints is throwaway
  (deleted on `make eks-down`).

## Read this doc

- Before any change, check the [roadmap](roadmap.md) and the [deviations
  log](architecture.md#deviations-log): they are the normative record.
- `local` is the demo/CI substrate; treat everything it runs as the minimal
  but *complete* platform, not as a reduced copy.
