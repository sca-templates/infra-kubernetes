# Status: Current State and Known Gaps

An honest picture of the platform today: what is deployed where, what is being
worked on, what is intentionally absent. Anything not listed here is either in
the component catalog ([architecture.md](architecture.md)) or does not exist.

The **delivery plan** (the 18 phases, their gates and the Work Log) now lives
in [roadmap.md](roadmap.md) and is tracked on the GitHub Projects board,
Milestones and Issues.

## Current state

**Phase 13 — Keycloak deployed; the NATS migration (C1–C4) completed with
Kafka/Strimzi removed; Phase B — backup layer landed and live
restore-validated on 2026-11-14 (Velero, CloudNativePG PITR, Vault Raft
snapshots).**
Phase 0 delivered the scaffold
(Makefile, `bootstrap/`, `argocd/` with the app-of-apps pattern, the CI
workflows, the service template, this docs set) and brought the local Floci
emulated EKS cluster up with ArgoCD. **Phase 1** lands cert-manager on the `local` profile
(fully-local: ArgoCD reconciles an in-cluster git serve instead of GitHub) and
ships the cluster smoke. **Phase 2** lands Vault — the secrets SSOT — as an HA
raft trio with TLS via a cert-manager leaf, an idempotent HA-aware seed, and a
green smoke. **Phase 3** lands External Secrets Operator: it projects Vault KV
into native Kubernetes `Secret`s through the `ClusterSecretStore vault`
(k8s-auth, TLS via the `vault-tls` leaf) with a short ~5 min refresh, and ships
a smoke proving a projected secret reaches `SecretSynced`. **Phase 4** landed
linkerd-crds, a CRD-only mesh base that was removed in D4 after the CNI-native
mTLS cutover. **Phase 5** lands CloudNativePG — the
PostgreSQL operator — at wave -10 in the `cloudnative-pg` namespace: chart
pinned 0.29.0 (operator 1.30.0), cluster-wide watch (`config.clusterWide`) so
the datastores can run in `data` at Phase 10, monitoring off until Phase 14,
with the 11 `postgresql.cnpg.io` CRDs all `Established`. **Phase 7** lands
redis-operator — the Redis operator — at wave
-10 in the `data` namespace (shared with the datastores it will manage, unlike
the dedicated `cloudnative-pg` namespace): chart pinned 0.26.1
(operator 0.26.0, `quay.io/opstree/redis-operator`), cluster-wide watch
(`watchNamespace: ""` renders no `WATCH_NAMESPACE`) so the Redis datastores can
run in `data` at Phase 12, webhook off, no PDB, with the 4
`redis.redis.opstreelabs.in` CRDs all `Established`. Its smoke goes one step
further than the other operators: a throwaway `Redis` CR in a scratch namespace
must produce a Ready StatefulSet and answer `PING` → `PONG`, which is the
honest proof that the CR is honored (the `Redis` CRD declares an empty status
object, so no condition can be asserted). The `Redis` CR lands at Phase 12.
**Phase 8** lands Kong — the
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
[ci-cd.md](ci-cd.md) for the smoke design. **Phase 9** landed the Linkerd
control plane as a dedicated `Application` per environment with an in-cluster
identity PKI; both it and its CRDs were removed in D4. **Phase 10** lands the PostgreSQL
datastores: three CNPG `Cluster`s in `data` at wave 40 across **all four**
environments — `postgres-app` (`app`/`app`), `keycloak-db`
(`keycloak`/`keycloak`) and `zitadel-db` (`zitadel`/`zitadel`, ADR-004 E1) on official
`ghcr.io/cloudnative-pg/postgresql:18.4-system-trixie` (the `system` flavor
carries the Barman Cloud binaries required by the native `barmanObjectStore`;
the operator-side migration to the Barman Cloud Plugin is a Phase B follow-up).
They are raw CRs, so
they ship through a **dedicated `Application` per environment**
(`argocd/postgres-app-<env>.yaml`, `directory.include: "*-<env>.yaml"`) rather
than the Helm `ApplicationSet`; `local`/`dev` run 1 instance, `qa`/`prod` run 3
with `preferred` anti-affinity (schedulable on the single-node promote
substrate). ESO projects the bootstrap credentials from
`secret/postgres-app/<env>`, `secret/keycloak-db/<env>` and
`secret/zitadel-db/<env>`.
`postgres-app` carries `pgvector` + `pg_stat_statements` (`pg_stat_statements.track:
all`; CNPG manages `shared_preload_libraries`) and `wal_level=logical`;
`keycloak-db` backs Keycloak (Phase 13) and `zitadel-db` backs Zitadel (ADR-004
E1). The catalog preload resolves the CNPG image from the raw manifests, and
`make smoke COMPONENT=postgres-app` validates the clusters, projected users, the
extensions and logical WAL.

**Phase 12** lands the Redis cache: a `RedisReplication` in `data` at wave 40 across all four
environments — 1 replica in local/dev, 3 in qa/prod with embedded Sentinel 3 (quorum 2,
master group `mymaster`). Images are pinned to `quay.io/opstree/redis:v7.4.11`,
`quay.io/opstree/redis-sentinel:v7.4.11` and `quay.io/opstree/redis-exporter:v1.44.0`.
The password is projected by ESO from `secret/redis/<env>` into `redis-password` and
consumed through `kubernetesConfig.redisSecret`; persistence is AOF on a PVC, the
exporter is enabled now (PodMonitor in Phase 14), and qa/prod add PDB + preferred
anti-affinity. Like postgres-app, the CRs ship through a **dedicated
`Application` per environment** (`argocd/redis-<env>.yaml`, `directory.include:
"*-<env>.yaml"`); `make smoke COMPONENT=redis` waits for the ExternalSecret and
StatefulSets, then exercises PING/SET/GET, AOF and (when present) Sentinel quorum.

**Phase 13** lands Keycloak — the OIDC identity provider — at wave 50 in the
`keycloak` namespace, as a **dedicated multi-source `Application` per
environment** (`argocd/keycloak-<env>.yaml`): the chart
(`codecentric/keycloakx` 7.4.0, Keycloak 26.8.1), the `$values` refs, the
per-env ExternalSecrets and the shared realm/TLS manifests are reconciled
together. This replaces the stale `bitnami/keycloak` plan (that chart is no
longer a viable pin). Keycloak uses the existing CNPG `keycloak-db` and all
credentials come from Vault: `secret/keycloak/admin` (bootstrap admin),
`secret/keycloak-db/<env>` (DB, basic-auth) and
`secret/keycloak/test-user/<env>` (smoke user). The realm `sca` is imported
declaratively from `ConfigMap/keycloak-realm-sca` (`--import-realm`) with the
`user` role, a public PKCE `sca-smoke` client and an env-substituted smoke
user. Kong serves the console at `https://keycloak.local` (local `:8443`) with
the `keycloak-tls` cert-manager leaf from `sca-ca`. Profiles: 1 replica local,
2 dev, 3 qa/prod (PDB in qa/prod; soft anti-affinity everywhere). `seed-vault.sh` is
now idempotent (`SEED_ROTATE=1` to rotate) and seeds the smoke user; the smoke
proves the realm import, discovery issuer, `login_required` redirect and a real
password-grant token accepted by userinfo (`make smoke COMPONENT=keycloak`).

**ADR-004 E1 (Zitadel, internal-only).** Zitadel is deployed as a dedicated
multi-source Application per env (`argocd/zitadel-<env>.yaml`, wave 50) from
chart `zitadel/zitadel` 10.5.0 (`ghcr.io/zitadel/zitadel:v4.19.2` and
`zitadel-login:v4.19.2`). It uses a new CNPG `zitadel-db` cluster (wave 40,
namespace `data`) and Vault paths `secret/zitadel/<env>` (masterkey + login
session secret) and `secret/zitadel-db/<env>` (username/password + DSN). There
is deliberately **no Ingress or edge TLS**: the h2c service stays internal and
the smoke port-forwards `svc/zitadel` with `Host: zitadel.local`, asserting OIDC
discovery but not client login flows. The issuer is the canonical
`https://zitadel.local` (port 443); Zitadel `v4.19.2` ignores non-standard
`ExternalPort` in discovery (`zitadel#11380`). Profiles: 1 replica local/dev, 3
qa/prod with PDB and preferred anti-affinity. The edge and service cutover are E2/E3;
the E1 live smoke gate passed on 2026-11-24.

**NATS migration (C1–C4).**
 NATS and NACK are deployed **idle** as the
ADR-005 event backbone; Kafka and Strimzi were removed in C3. `nats`
(chart/appVersion `2.15.2`, namespace `data`, wave 40) runs a single JetStream
node in `local`/`dev` and a 3-node
JetStream cluster with a PDB and preferred anti-affinity in `qa`/`prod`; it
ships **no** `Stream`/`Consumer` CRs. `nack` (chart `0.35.0` / controller
`0.24.0`, namespace `nats`, wave 50) installs the six JetStream CRDs and watches
all namespaces, so it starts after the server it connects to. Both are generated
by the optional `messaging-<env>` ApplicationSet from
`argocd/messaging/<env>/{nats,nack}.yaml`: remove those descriptors to switch the
environment to SNS/SQS mode, where nothing is deployed in-cluster. The runtime
contract is Vault KV-v2 `secret/messaging/<env>` (`mode` + endpoints);
`bootstrap/seed-vault.sh` seeds local `mode=nats`. The toggle and service-owned
topology are documented in [messaging.md](messaging.md). Kafka/Strimzi were removed in
C3, taking their CRs, dedicated Applications, values and smokes with them.
`make smoke COMPONENT=nack` (CRDs `Established`,
cluster-wide watch) and `make smoke COMPONENT=nats` (JetStream enabled, zero
streams) are the convergence gates.

**Linkerd replacement (D0–D5 complete).** The
static inventory and option evaluation are complete in
[ADR-008](adr/adr-008-cni-native-mtls.md). D1 added the
[Cilium PoC harness](../poc/cni-mtls/README.md); D2 ran it seven times and
stabilized the substrate, chart source, values and BPF mount, but cross-node
HTTP still timed out with no WireGuard handshake or tunnel traffic. Both tunnel
and native routing were tried. [ADR-009](adr/adr-009-calico-wireguard-fallback.md)
opened the Calico fallback and the
[Calico PoC harness](../poc/calico-wireguard/README.md) passed its D2 gate on
2026-11-17: both nodes Ready, cross-node HTTP, one WireGuard peer per node, a
recent handshake and positive byte counters. D3 landed the bootstrap-managed
Calico `v3.31.7` + WireGuard + pinned kube-proxy substrate, per-env CNI profiles
and a single-node smoke; `make eks-up` and `make smoke COMPONENT=cni` passed on
2026-11-20. The full platform gate also passed that day via `make bootstrap
ENV=local` and `make validate`: 13 local Applications converged
`Synced`/`Healthy` on `feature/decisions` with the optional messaging tier
enabled, and the component smoke sweep was green. D4 removed the Linkerd
Applications, CRDs, identity PKI, smokes, annotations and repository wiring; D5
closed the docs. The `main` catalog has 11 Applications because `nats`/`nack`
are absent there. WireGuard is node-to-node transport encryption, not workload
mTLS.

| Fact | Value |
| --- | --- |
| Repository | `infra-kubernetes` (local, fully-local git serve; published to GitHub before promotion) |
| Deployed components | ArgoCD (bootstrap), cert-manager (Phase 1), Vault (Phase 2), external-secrets (Phase 3), cloudnative-pg (Phase 5), redis-operator (Phase 7), Kong (Phase 8), postgres-app/keycloak-db/zitadel-db (Phase 10 + ADR-004 E1), Redis (Phase 12), Keycloak (Phase 13), Zitadel (ADR-004 E1, internal-only), NACK/NATS (NATS migration C1–C4, idle, optional per env), Velero (Phase 18; backup layer expanded in Phase B, live restore-validated 2026-11-14) |
| `platform-root-local` | not used — `local` runs no services, so there is no root Application; `make bootstrap ENV=local` seeds the catalog wiring (`apps-local` + `messaging-local` + `kong-local` + `postgres-app-local` + `redis-local` + `keycloak-local` + `zitadel-local`) host-side |
| `platform-local` ApplicationSet | present, six mandatory elements (`cert-manager` wave -20, `external-secrets` + `cloudnative-pg` + `redis-operator` wave -10, `vault` wave 0, `velero` wave 80) |
| `messaging-local` ApplicationSet | present, optional `nats` (wave 40) + `nack` (wave 50) generated by the git files generator over `argocd/messaging/local/*.yaml`; remove the two descriptors for SNS/SQS mode |
| cert-manager app | `cert-manager-local` `Synced` + `Healthy`; `sca-ca` ClusterIssuer `Ready`; leaf Certificate smoke green |
| vault app | `vault-local` `Synced` + `Healthy`; HA raft trio, TLS via `vault-tls` leaf; `make smoke COMPONENT=vault` → initialized=true sealed=false; seed idempotent and HA-aware |
| external-secrets app | `external-secrets-local` `Synced` + `Healthy`; `ClusterSecretStore vault` Ready (k8s-auth `external-secrets`, TLS via `vault-tls`); short `refreshInterval` (5m); `make smoke COMPONENT=external-secrets` → throwaway ExternalSecret `SecretSynced` + data verified |
| cloudnative-pg app | `cloudnative-pg-local` `Synced` + `Healthy`; operator Deployment `cloudnative-pg` Ready (chart 0.29.0 / operator 1.30.0); 11 `postgresql.cnpg.io` CRDs present + `Established`; `make smoke COMPONENT=cloudnative-pg` green |
| redis-operator app | `redis-operator-local` `Synced` + `Healthy` in namespace `data`; operator Deployment `redis-operator` Ready (chart 0.26.1 / operator 0.26.0); watches all namespaces (no `WATCH_NAMESPACE` env); 4 `redis.redis.opstreelabs.in` CRDs present + `Established`; `make smoke COMPONENT=redis-operator` → throwaway `Redis` CR honored (StatefulSet ready + `PING` → `PONG`) |
| kong app | `kong-local` `Synced` + `Healthy` in namespace `kong` (dedicated Application, **no SSA**); chart 3.4.1, gateway Deployment `kong` Ready (containers `ingress-controller` KIC 3.5.5 + `proxy` kong 3.9.4), DB-less (`KONG_DATABASE=off`); IngressClass `kong`; `configuration.konghq.com` CRDs `Established`; `Certificate/kong-proxy` Ready (leaf off `sca-ca`); declarative `Ingress kong-demo` + `KongPlugin demo-termination`; `make smoke COMPONENT=kong` → `GET https://kong.local/demo` → 200 |
| postgres-app app | `postgres-app-local` `Synced` + `Healthy` (dedicated Application, raw CRs); CNPG `Cluster postgres-app` Ready (1 instance local; image `18.4-system-trixie`), `keycloak-db` + `zitadel-db` Ready (1 instance each local); ESO `postgres-app-credentials` + `keycloak-db-credentials` + `zitadel-db-credentials` `SecretSynced`; `pg_stat_statements` + `vector` + `wal_level=logical` verified through `app@app`; `make smoke COMPONENT=postgres-app` green |
| nats app | `nats-local` `Synced` + `Healthy` (optional `messaging-local` ApplicationSet element); chart/appVersion `nats/nats` 2.15.2 with JetStream enabled and a file-store PVC (1 node local/dev, 3-node JetStream cluster qa/prod); no `Stream`/`Consumer` CRs; `make smoke COMPONENT=nats` → server Ready, JetStream enabled, zero streams |
| nack app | `nack-local` `Synced` + `Healthy` (optional `messaging-local` ApplicationSet element, namespace `nats`); chart `nats/nack` 0.35.0 / controller 0.24.0; six `*.jetstream.nats.io` CRDs `Established`; watches all namespaces; `make smoke COMPONENT=nack` green |
| messaging contract | Vault KV-v2 `secret/messaging/local` `mode=nats` + `nats_url`; consumers project it through ESO. SNS/SQS coordinates (topic/queue/region, optional endpoint/credentials) are provisioned out of band when that mode is enabled |
| redis app | `redis-local` `Synced` + `Healthy` (dedicated Application, raw CRs); `RedisReplication/redis` (1 replica local/dev) with embedded Sentinel only in qa/prod (3/3, mymaster); password from ESO `redis-password` via `secret/redis/<env>`; AOF on PVC, `redisExporter` enabled; `make smoke COMPONENT=redis` → PING/SET/GET and AOF verified; Sentinel checked in qa/prod |
| keycloak app | `keycloak-local` `Synced` + `Healthy` (dedicated multi-source Application); chart `codecentric/keycloakx` 7.4.0 / Keycloak 26.8.1; StatefulSet `keycloak` Ready; `ExternalSecret/keycloak-admin` + `keycloak-db-credentials` + `keycloak-test-user` `SecretSynced`; realm `sca` imported from `ConfigMap/keycloak-realm-sca`; `Certificate/keycloak-tls` Ready; Kong Ingress `keycloak.local`; `make smoke COMPONENT=keycloak` → discovery issuer, `login_required` redirect, password-grant token + userinfo green |
| zitadel app | `zitadel-local` `Synced` + `Healthy` (dedicated multi-source Application, internal-only E1); chart `zitadel/zitadel` 10.5.0 / app `v4.19.2`; three ExternalSecrets `SecretSynced`; runtime ConfigMap applied as a normal resource at wave `-6`; `Job/zitadel-init` + `Job/zitadel-setup` Complete at waves `-5`/`-4`; Deployments `zitadel` + `zitadel-login` Ready; no Ingress; `make smoke COMPONENT=zitadel` green → h2c discovery issuer `https://zitadel.local` |
| git-local-serve | in-cluster git daemon (`git://<node>:9418/sca-infra.git`) `Ready` |
| Observability / smoke CI | cluster smoke `pr-cluster.yml` **shipped** (Phase 1): selective on PRs as the **required `Smoke` check** on `main` + manual `workflow_dispatch`; no `push` smoke. Multi-component PRs smoke every touched component in one run (one boot/cloud/teardown); changes to the smoke framework (`bootstrap/smoke-*`, `argocd/**`, `Makefile`) resolve to `cert-manager` so the machinery is self-validated; CNI substrate changes resolve to `cni`; the pinned toolchain is cached (`actions/cache`, keyed on `versions.sh`) (see [ci-cd.md](ci-cd.md)) |
| CNI substrate (dev/CI tooling) | D3 implementation landed with **local substrate smoke passed** on 2026-11-20: `make eks-up` starts Floci with bundled CNI disabled and k3s pinned to `v1.34.1-k3s1`, then `bootstrap/cni-emulator.sh` installs Calico `v3.31.7` (iptables + VXLAN + WireGuard, `MTU=1440`) and pinned kube-proxy `v1.34.1` with `--conntrack-max-per-core=0`; `make smoke COMPONENT=cni` runs before `make bootstrap` on every smoke. The first full-platform attempt failed because the D3 kube-proxy tried to write read-only `/proc/sys/net/netfilter`, breaking ClusterIP and the ArgoCD pre-install hook; the internal API probe now fails fast on that condition. `envs/<env>/cni.yaml` enforces `local` and documents the external contract. **Not a catalog Application**; rollback is a D3 revert plus `make eks-down` (see [ci-cd.md](ci-cd.md)) |
| Cloud integration smoke | every smoke run also proves the cluster reaches the local cloud emulator (Floci): `make cloud-up` / `make smoke COMPONENT=cloud` green — bucket created and object round-tripped from an in-cluster Job; on by default, `--no-cloud` / `SMOKE_CLOUD=0` opts out. **Dev/CI tooling, not a platform component** (see [ci-cd.md](ci-cd.md)) |
| EKS substrate smoke | the required `Smoke` job boots the **full platform** on Floci's emulated **EKS** (real single-node k3s + ECR), the platform's only cluster substrate: `make eks-up` → `make smoke COMPONENT=cni` (substrate gate) → `make bootstrap ENV=local` → Vault seeded before the health gate → every `<name>-local` Application `Synced`/`Healthy` → `make smoke COMPONENT=eks` green (ECR push + in-cluster pull round-trip via the node registry mirror) → endpoint smoke. Proves EKS integration (IAM kubeconfig) + the ECR image path. **Dev/CI tooling, not a platform component** (see [ci-cd.md](ci-cd.md)) |
| Security CI | checkov **baseline gate** active (Phase 1): `.github/checkov-baseline.json` documents the local-git-server pod findings; new IaC findings fail the PR; re-evaluated at Phase 18 (see [security.md](security.md)) |
| Release automation | **path-scoped** triggers active (see [versioning.md](versioning.md)): only `feat`/`fix` commits touching the platform surface open release PRs (`exclude-paths` in `.release-please-config.json`); release-please runs on `push: main` only via the shared `shared-release-flow.yml` wrapper; tag signing runs when a release is created (manual dispatch re-sign removed) |
| Release promotion | tags are cut automatically and the release goes out as a **full release held off `latest`**; `release-publish.yml` (manual) is the only step that moves the `latest` pointer, on a human go/no-go (see [versioning.md](versioning.md)) |
| dev / qa / prod clusters | pending (provisioned by terraform/ansible, outside this repo) |

## Known accepted limitations

| # | Limitation | Current behavior | To close |
| --- | --- | --- | --- |
| 1 | **Fully-local git serve (dev, not GitHub)** | Local **dev** ArgoCD can reconcile an in-cluster git serve (`git://<node>:9418`) instead of GitHub: `make local-git-up` mirrors this repo's HEAD verbatim onto the serve (`bootstrap/render-served-apps.sh`), while `make bootstrap` seeds the ArgoCD wiring (`argocd/apps-local.yaml`, `argocd/messaging-local.yaml`, `argocd/kong-local.yaml`) host-side with the placeholders resolved. The CI cluster smoke does **not** use the serve — it seeds the wiring host-side via `make bootstrap` | Publish the repo and swap `GIT_REPO_URL` back to GitHub to exercise the real source-of-truth path; the git serve stays dev-only tooling |
| 2 | **dev / qa / prod clusters pending** | Not provisioned (terraform/ansible outside this repo) | Provision per env; promote via `promote-test` (see [workflow.md](workflow.md)) |
| 3 | **OpenSSF Best Practices badge — silver blocked** | All silver criteria are met except `contributors_unassociated` and `bus_factor` (≥2): the project has a single maintainer (`CODEOWNERS` = `@Santiago1010`) | Achieved once a second **unassociated** contributor joins and is reflected in `CODEOWNERS` + `.github/GOVERNANCE.md`; passing badge is already achievable (see [.github/GOVERNANCE.md](../.github/GOVERNANCE.md), [docs/ci-cd.md](ci-cd.md)) |
| 4 | **OpenSSF Best Practices badge — gold blocked** | Beyond the silver gaps, gold requires `two_person_review` (≥50% of changes reviewed by someone other than the author), which is unrealisable while there is a single maintainer; all other gold criteria are Met or N/A (see [.github/SECURITY.md](../.github/SECURITY.md) security review, SPDX + copyright headers per source file) | Unblocked together with silver once a second, **unassociated** reviewer/maintainer exists; `two_person_review` then requires an explicit second reviewer on gold PRs |
| 5 | **NATS JetStream is idle and unauthenticated** | The ready-but-idle tier ships no `Stream`/`Consumer` CRs and no client auth; the server is reachable only in-cluster (`nats.data.svc.cluster.local:4222`). The `secret/messaging/<env>` contract exists, but no consumer uses it yet | Add NATS accounts/credentials with the first consumer, wire them through ESO and extend the contract; see [ADR-005](adr/adr-005-kafka-to-nats-jetstream.md) and [messaging.md](messaging.md) |
| 6 | **No service-mesh L7 features or golden signals** | The CNI substrate provides authenticated node-to-node transport only; there is no workload identity, retry/timeout/traffic split or mesh request metrics. Phase 14 monitors native targets only | Requires a separate ADR before reintroducing a mesh or L7 observability; see [ADR-008](adr/adr-008-cni-native-mtls.md) and [observability-radar.md](observability-radar.md) |

## Intentional exclusions

- **No MinIO, no Unleash, no KafkaConnect/Debezium, no kafka-ui in-cluster.**
  They are deliberate scope cuts of the restart plan; Velero's local backend is
  the Floci S3 emulator.
- **No Consul and no Consul-k8s in-cluster** (ADR-001): native Kubernetes DNS
  replaces it.
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

## Migration Status (Phase A)

| Component/Migration | Status | Notes |
| --- | --- | --- |
| Keycloak → Zitadel | **E1 validated; E2 implemented (live gate pending), E3 pending** | E0 inventoried dependencies; E1 deployed and live-validated Zitadel internally with a dedicated `zitadel-db`. E2 adds Kong/TLS Ingresses and the edge smoke but still needs the live gate; E3 has a [cutover runbook](zitadel-cutover.md) and no service changes yet. See [ADR-004](adr/adr-004-keycloak-to-zitadel.md). |
| Kafka/Strimzi → NATS JetStream | **Done (C1–C4)** | NATS + NACK deployed idle (no `Stream`/`Consumer` CRs) via the optional `messaging-<env>` ApplicationSet; remove `argocd/messaging/<env>/{nats,nack}.yaml` for SNS/SQS mode. Contract `secret/messaging/<env>` carries `mode` + endpoints. Kafka/Strimzi removed in C3; the C4 runbook for the toggle and service-owned topology is in [messaging.md](messaging.md). |
| Linkerd → CNI-native mTLS | **Done (D0–D5)** | Static inventory and option evaluation in [ADR-008](adr/adr-008-cni-native-mtls.md); [poc/cni-mtls](../poc/cni-mtls/README.md) records the failed Cilium `1.20.5` gate. [ADR-009](adr/adr-009-calico-wireguard-fallback.md) and [poc/calico-wireguard](../poc/calico-wireguard/README.md) pin the Calico `v3.31.7` fallback, whose D2 gate passed on 2026-11-17 with cross-node HTTP and WireGuard peer/handshake/counter evidence. D3 landed `bootstrap/cni-emulator.sh`, `envs/<env>/cni.yaml` and `bootstrap/smoke-cni.sh` as bootstrap substrate (not a catalog Application); D4 removed Linkerd and D5 closed the docs. |
| Velero + Backups | **Done** | The three layers are implemented and live restore-validated on 2026-11-14: Velero scheduled backups, CNPG Barman base backups + WAL/PITR, and Vault Raft snapshot CronJob. `local` uses Floci S3; `dev`/`qa`/`prod` expect external buckets and Vault-provisioned credentials. See [backups.md](backups.md#validation-status). |
| CNPG RDS replacement | **Done** | The PITR + latest-backup restore smoke (`bootstrap/smoke-postgres-app.sh`) passed live on 2026-11-14, closing the RDS replacement gate. |

## Phase B additions (backup layer)

| Component | Namespace | Status | Notes |
| --- | --- | --- | --- |
| velero | velero | deployed (schedule + restore live-validated 2026-11-14) | Scheduled Kubernetes-object backup configs in all four envs; `local` uses Floci S3, external environments use their own bucket. The `floci-buckets` Job creates the local buckets. The schedule template re-ran to `Completed` (639 items; `velero-critical-namespaces-manual-20261114154830`) after the Floci bucket was recreated, and `bootstrap/smoke-velero.sh` performs a backup → delete namespace → restore round-trip. |
| CNPG backups + PITR | data | deployed (live restore validated 2026-11-14) | All three `Cluster`s (`postgres-app`, `keycloak-db`, `zitadel-db`) are configured to write Barman base backups + WAL to object storage; daily `ScheduledBackup`s; credentials via `secret/cnpg/<env>`. `bootstrap/smoke-postgres-app.sh` exercises PITR on `postgres-app` and latest-backup restore on `keycloak-db`, and also verifies `zitadel-db` connectivity. |
| Vault Raft snapshots | vault | deployed (restore drill validated 2026-11-14) | `CronJob/vault-raft-snapshot` is configured to save/validate/upload a Raft snapshot and apply retention; credentials via `secret/vault-snapshot/<env>`. `bootstrap/smoke-vault.sh` triggers a real Job and asserts `VAULT_SNAPSHOT_OK` + `VAULT_SNAPSHOT_UPLOADED`; the manual Raft restore drill recovered a canary KV. |

The backup operations, schedules, retention values, and restore runbooks live in
[backups.md](backups.md). Live restore validation completed on 2026-11-14 (see
[Validation status](backups.md#validation-status)).
