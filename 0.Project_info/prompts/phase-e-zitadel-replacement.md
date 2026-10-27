# Phase E: Keycloak → Zitadel (Complete Replacement)

## Objective
Replace Keycloak with Zitadel completely. Keycloak will be REMOVED ENTIRELY. No keeping Keycloak around.

## Context
From Phase A. User confirmed: "Sí, se elimina keycloack, pero sí se reemplaza por Zitadel"

## Tasks

### 1. Complete Inventory (from Phase A)
- Review full inventory of Keycloak dependencies
- Map all OIDC clients, realms, users, roles
- Find all Kong routes to Keycloak
- Find all service integrations
- Check keycloak-db usage

### 2. Research Zitadel
- Evaluate Zitadel deployment (Helm chart or manifests)
- Plan integration with CNPG (can use new DB or existing)
- Plan OIDC configuration
- Understand migration path

### 3. Deploy Zitadel in Parallel
- Add Zitadel to infrastructure/
- Create ArgoCD apps
- Configure with CNPG
- Set up basic realm/project

### 4. Migrate Configuration
- Recreate OIDC clients in Zitadel
- Migrate necessary users/roles
- Configure redirects/callbacks
- Update Kong routes
- Test authentication flows

### 5. Migrate Services
- Update all services to use Zitadel endpoints
- Update configurations
- Test thoroughly

### 6. Remove Keycloak Completely
- Remove infrastructure/keycloak/
- Remove argocd/keycloak-*.yaml
- Remove keycloak-db from postgres-app if not used (check dependencies)
- Remove all secrets (secret/keycloak/*)
- Remove Kong routes to Keycloak
- Remove from apps-*.yaml, envs, docs
- Update all references

### 7. Cleanup
- Remove namespace keycloak
- Clean up Vault paths
- Validate no broken references

## Constraints
- Complete replacement - no parallel running long-term
- Must find ALL Keycloak references
- Evaluate keycloak-db removal if unused
- Follow GitOps patterns

## Deliverables
- Zitadel fully deployed and operational
- All auth migrated
- Keycloak completely removed
- keycloak-db evaluated and cleaned if possible
- All references updated
- Docs updated
