# ADR-004: Replace Keycloak with Zitadel

## Status

Accepted — E1 (internal deployment) validated; E2 (Kong/TLS edge) implemented and
awaiting the live smoke gate; E3 runbook ready, service cutover pending.

## Context

Keycloak is currently deployed as the OIDC identity provider. We need to evaluate alternatives for cost/operational efficiency.

## Decision

Replace Keycloak with Zitadel. Keycloak will be completely removed from the platform with no parallel long-term deployment.

## Consequences

- Need to migrate all OIDC clients and configuration
- Must inventory all dependencies before removal
- keycloak-db in CNPG may be removable if unused
- All Kong routes and service integrations must be updated
- Authentication flows will change

## Implementation

- **E0 — inventory (closed)**: [migration-inventory-phase-a.md](../migration-inventory-phase-a.md)
  records the current Keycloak dependencies.
- **E1 — internal deployment (landed)**: `zitadel-<env>` Applications at wave 50
  with a dedicated CNPG `zitadel-db` at wave 40, Vault/ESO secrets and an
  internal-only h2c smoke. No Ingress or edge TLS yet; see
  [architecture.md](../architecture.md#deviations-log),
  [status.md](../status.md) and [ci-cd.md](../ci-cd.md#zitadel-smoke-e1e2).
- **E2 — edge (implemented, live gate pending)**: Kong Ingresses at wave 50 route
  `https://zitadel.local` to the h2c `zitadel` Service via
  `konghq.com/protocol: grpc`; `cert-manager` issues `zitadel-tls` from `sca-ca`,
  and a separate Ingress routes the `/ui/v2/login` UI to `zitadel-login`. The
  smoke now asserts discovery through the real Kong/TLS edge; see
  [ci-cd.md](../ci-cd.md#zitadel-smoke-e1e2).
- **E3 — cutover (runbook ready)**: [zitadel-cutover.md](../zitadel-cutover.md)
  defines the per-client migration sheet, dev/qa promotion and prod version-pin
  gate, validation, rollback and the Keycloak retirement gate. Service repos own
  the actual client changes.
