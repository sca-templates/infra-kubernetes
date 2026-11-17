# Phase A Migration Inventory

## 1. Keycloak References (403 total found)

Keycloak components to remove and replace with Zitadel:

- **ArgoCD apps**: keycloak-*.yaml (4 envs)
- **Infrastructure**: infrastructure/keycloak/
- **Env configs**: envs/*/keycloak.yaml
- **Database**: keycloak-db cluster in postgres-app (may be removable)
- **Secrets**: secret/keycloak/*(admin, test-user), secret/keycloak-db/*
- **Namespace**: keycloak
- **Kong routes**: Routes to keycloak.local
- **Service template**: May have OIDC integration
- **Docs**: Extensive documentation to update

**Action**: Complete inventory of OIDC clients, must migrate to Zitadel or remove.

## 2. Linkerd References (D0 static inventory, 2026-11-17)

> The earlier "3 found" estimate was incomplete. The D0 checkpoint found 49
> tracked files outside `CHANGELOG.md`: 33 runtime/wiring/tooling files and 16
> docs/history files. ADR-008 owns the evaluation, the non-equivalence to
> workload mTLS and the D0–D5 gates; this section is the removal checklist.

Runtime and wiring:

- **ArgoCD**: `argocd/linkerd-<env>.yaml` (4 dedicated control-plane
  Applications) and the `linkerd-crds` element in `argocd/apps-<env>.yaml`
  (4); `argocd/install-values.yaml` comment.
- **Charts and overlays**: `infrastructure/linkerd/`,
  `infrastructure/linkerd-crds/` and `envs/<env>/linkerd{,-crds}.yaml` (8).
- **Service template**: `charts/service-template/templates/deployment.yaml`,
  `values.yaml` and `values.schema.json` (`linkerd.io/inject`).
- **Tooling**: `Makefile`, `bootstrap/smoke-linkerd.sh`,
  `bootstrap/smoke-linkerd-crds.sh`, `bootstrap/smoke-target.sh` and
  `bootstrap/versions.sh`; `.gitleaks.toml` (identity-anchor exemption) and
  `.vscode/settings.json`.

Docs and history:

- Current-state docs (`README.md`, `AGENTS.md`, `docs/architecture.md`,
  `docs/status.md`, `docs/roadmap.md`, `docs/roadmap/linkerd*.md` and related
  guides) are updated as each D checkpoint lands.
- `docs/adr/adr-001-no-consul.md`, `docs/adr/adr-002-linkerd-to-cni-mtls.md`,
  Work Log rows and `CHANGELOG.md` remain as the decision and migration
  history; do not rewrite them as if Linkerd had never been deployed.
- [ADR-008](adr/adr-008-cni-native-mtls.md) is the source of truth for the
  proposed replacement; `status.md` keeps the deployed/until-cutover state.

**Action**: D0 complete (research only). D1 adds the disposable PoC files, D2
gates on their evidence, D3 lands the CNI substrate, D4 removes the runtime
surfaces above and D5 closes the docs. Service repositories are outside this
repo and must drop their own injection annotations at D4.

## 3. Kafka/Strimzi References (203 total found)

> **Historical inventory (ADR-005 C1–C4).** All items below were removed in C3
> (2026-11-16); NATS/NACK are the sole event backbone. C4 (2026-11-17) added the
> toggle and service-owned topology runbook in [messaging.md](messaging.md).
> The list is kept as the migration record.

- **Strimzi operator**: infrastructure/strimzi/, in all apps-*.yaml
- **Kafka CRs**: infrastructure/kafka/, argocd/kafka-*.yaml
- **Env configs**: envs/*/strimzi.yaml
- **Secrets**: secret/kafka/*
- **Namespace**: strimzi, data contains Kafka CRs
- **Smoke tests**: bootstrap/smoke-kafka.sh

**Action**: Completed in C1–C4 — NATS JetStream (togglable) replaced
Kafka/Strimzi; see [messaging.md](messaging.md) for the toggle procedure.

## 4. CNPG/Postgres References

- postgres-app with app and keycloak-db clusters
- Need to ensure backups/PITR for RDS replacement

## 5. Velero (done)

- Phase 18 and the Phase B backup layer landed; live restore validation passed
  on 2026-11-14
- Current state and runbooks live in [status.md](status.md) and
  [backups.md](backups.md); no migration work remains here

## Next Steps

1. Keep statuses cross-linked from [status.md](status.md) and the global Work
   Log in [roadmap.md](roadmap.md); do not duplicate deployment state here
2. Run ADR-008 D1 (disposable PoC files) only after D0 is committed
3. Inventory Keycloak/OIDC clients in E0 before any Zitadel cutover
