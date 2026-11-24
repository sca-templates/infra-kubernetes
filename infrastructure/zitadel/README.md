# Zitadel

OIDC identity provider replacing Keycloak ([ADR-004](../../docs/adr/adr-004-keycloak-to-zitadel.md)). The API and Login UI run behind a Kong/TLS edge; the cutover runbook lives in [docs/zitadel-cutover.md](../../docs/zitadel-cutover.md).

- Upstream chart: [zitadel/zitadel](https://charts.zitadel.com) (`10.5.0`, app `v4.19.2`)
- Purpose: OIDC IdP for the platform and its services
- Namespace: `zitadel`
- Wave: 50
- Database: CNPG `zitadel-db` in `data` (wave 40)
- Secrets: Vault/ESO, never literals in git
