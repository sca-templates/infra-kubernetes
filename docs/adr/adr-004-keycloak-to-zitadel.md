# ADR-004: Replace Keycloak with Zitadel

## Status
Proposed

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
- Deploy Zitadel in parallel initially
- Migrate configuration
- Update all services
- Remove Keycloak completely
