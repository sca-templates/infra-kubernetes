# ADR-004: Replace Keycloak with Zitadel

## Status

Accepted — E1 (internal deployment) landed; E2 (edge) and E3 (service cutover)
are pending.

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
  [status.md](../status.md) and [ci-cd.md](../ci-cd.md#zitadel-internal-smoke-e1).
- **E2 — edge**: expose Zitadel with an h2c-capable proxy and TLS, then port the
  smoke to the real discovery URL.
- **E3 — cutover**: migrate OIDC clients/configuration from Keycloak, update all
  services, then remove Keycloak and `keycloak-db` completely.
