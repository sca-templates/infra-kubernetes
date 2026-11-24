# Zitadel

OIDC identity provider replacing Keycloak ([ADR-004](../../docs/adr/adr-004-keycloak-to-zitadel.md)). E1 deploys the API, Login UI and internal-only h2c service; the edge is deferred to E2.

- Upstream chart: [zitadel/zitadel](https://charts.zitadel.com) (`10.5.0`, app `v4.19.2`)
- Purpose: OIDC IdP for the platform and its services
- Namespace: `zitadel`
- Wave: 50
- Database: CNPG `zitadel-db` in `data` (wave 40)
- Secrets: Vault/ESO, never literals in git
