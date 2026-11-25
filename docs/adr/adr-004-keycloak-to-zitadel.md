# ADR-004: Replace Keycloak with Zitadel

## Status

Accepted and implemented — E1 (internal deployment) and E2 (Kong/TLS edge)
validated; E3 had no OIDC clients or service deployments to cut over; E4 retired
Keycloak from the platform. Zitadel is the sole OIDC identity provider.

## Context

Keycloak had been deployed as the OIDC identity provider. We needed to evaluate alternatives for cost/operational efficiency.

## Decision

Replace Keycloak with Zitadel. Keycloak was completely removed from the platform with no parallel long-term deployment.

## Consequences

- OIDC clients and configuration were inventoried before removal
- No service client existed at retirement time; the per-client runbook stays for future services
- The `keycloak-db` CNPG cluster was removed with E4
- Kong routes now serve Zitadel only
- Authentication flows for services will use Zitadel from their first deployment

## Implementation

- **E0 — inventory (closed)**: [migration-inventory-phase-a.md](../migration-inventory-phase-a.md)
  recorded the pre-migration Keycloak dependencies.
- **E1 — internal deployment (validated)**: `zitadel-<env>` Applications at wave
  50 with a dedicated CNPG `zitadel-db` at wave 40, Vault/ESO secrets and an
  initial internal-only h2c smoke. See
  [architecture.md](../architecture.md#deviations-log),
  [status.md](../status.md) and [ci-cd.md](../ci-cd.md#zitadel-smoke-e1e2).
- **E2 — edge (validated)**: Kong Ingresses at wave 50 route
  `https://zitadel.local` to the h2c `zitadel` Service via
  `konghq.com/protocol: grpc`; `cert-manager` issues `zitadel-tls` from `sca-ca`,
  and a separate Ingress routes the `/ui/v2/login` UI to `zitadel-login`. The
  live gate passed on 2026-11-24 with the smoke asserting discovery and login UI
  through the real Kong/TLS edge; see [ci-cd.md](../ci-cd.md#zitadel-smoke-e1e2)
  and the [Work Log](../roadmap.md#work-log-global-reverse-chronological).
- **E3 — cutover (no clients yet)**: there were no OIDC clients or service
  deployments, so there was nothing to migrate and no service repo change to make.
  [zitadel-cutover.md](../zitadel-cutover.md) remains the historical per-client
  migration sheet, dev/qa promotion and prod version-pin gate, validation and
  rollback reference for services that used Keycloak before retirement. Service
  repos own the actual client changes.
- **E4 — platform retirement (closed)**: the `keycloak-<env>` Applications,
  overlays, chart, realm/TLS manifests, smoke, Vault seeds and paths,
  `keycloak-db` CNPG clusters/backups, CI/Makefile/Velero wiring and catalog
  rows were removed. The CNPG latest-backup restore smoke now uses `zitadel-db`,
  and the External Secrets smoke projects `secret/postgres-app/<env>`. Zitadel is
  the only identity plane; no cluster-side Keycloak resource is retained for
  rollback.
