# Phase A Migration Inventory

## 1. Keycloak References (historical E0 inventory, closed in E4)

> **Historical inventory (ADR-004 E0–E4).** The items below were the pre-migration
> surfaces. E3 closed with no OIDC clients to cut over, and E4 removed every
> runtime, secret, database and wiring surface. The list is kept as the migration
> record; current state lives in [status.md](status.md).

Removed with E4:

- **ArgoCD apps**: `argocd/keycloak-*.yaml` (4 envs)
- **Infrastructure**: `infrastructure/keycloak/`
- **Env configs**: `envs/*/keycloak.yaml`
- **Database**: `keycloak-db` CNPG clusters, credentials and backup schedules
- **Secrets**: `secret/keycloak/*` (admin, test-user), `secret/keycloak-db/*`
- **Namespace**: `keycloak`
- **Kong routes**: routes to `keycloak.local`
- **Smoke/CI**: `bootstrap/smoke-keycloak.sh`, smoke targets, Makefile and CI path filters
- **Docs**: current-state catalog, status, architecture, roadmap and CI/CD rows

**Action**: Closed in E4 — Zitadel is the sole identity plane; no service clients
required migration.

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
- [ADR-008](adr/adr-008-cni-native-mtls.md) records the accepted replacement
  decision and the D0–D5 closeout; [ADR-009](adr/adr-009-calico-wireguard-fallback.md)
  records the selected Calico fallback; `status.md` reports the current CNI
  substrate.

**Action**: D0 complete (research only). D1 added the disposable
[Cilium PoC harness](../poc/cni-mtls/README.md); D2 failed on Cilium and passed
on the [Calico PoC harness](../poc/calico-wireguard/README.md). D3 has landed the
chosen CNI substrate as bootstrap tooling (`bootstrap/cni-emulator.sh`,
`envs/<env>/cni.yaml`, `bootstrap/smoke-cni.sh`), with its fresh-cluster
substrate gate passed on 2026-11-20; D4 removed the runtime surfaces above and
D5 closed the docs.
Service repositories are outside this repo; the only in-repo injection surface
was the service template, removed in D4, and downstream annotation removal is an
out-of-band follow-up.

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

- postgres-app with app and zitadel-db clusters; keycloak-db was removed in E4
- Backups/PITR are live-validated for RDS replacement (see [backups.md](backups.md))

## 5. Velero (done)

- Phase 18 and the Phase B backup layer landed; live restore validation passed
  on 2026-11-14
- Current state and runbooks live in [status.md](status.md) and
  [backups.md](backups.md); no migration work remains here

## Next Steps

1. Keep statuses cross-linked from [status.md](status.md) and the global Work
   Log in [roadmap.md](roadmap.md); do not duplicate deployment state here
2. D2 evidence is complete: the ADR-008 Cilium gate failed and the ADR-009 Calico gate passed; proceed with D3
3. Keycloak/OIDC client inventory closed in E0; Zitadel retirement complete in E4
