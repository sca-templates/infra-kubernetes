# Zitadel cutover runbook (ADR-004 E3)

This runbook is the platform-side procedure for migrating OIDC clients from
Keycloak to Zitadel. It does not change service repositories: application
manifests, client credentials and redirect URIs continue to be owned by each
service's `deploy/` directory.

## Current state

No OIDC clients or service deployments existed when E3 closed, so no cutover was
performed. E4 subsequently retired Keycloak from the platform; Zitadel is now
the only identity plane. This runbook remains the historical procedure for any
service that migrated from Keycloak before retirement, and future services
onboard directly to Zitadel. The platform-side E1/E2 gates are green.

## Scope and preconditions

- **E1** is live: `zitadel-<env>` Applications are `Synced`/`Healthy` with the
  dedicated `zitadel-db` CNPG cluster and Vault/ESO projections.
- **E2** is live: `make smoke COMPONENT=zitadel` passes through Kong TLS at
  `https://zitadel.local/.well-known/openid-configuration`, with the canonical
  issuer `https://zitadel.local`.
- The dependency inventory in
  [migration-inventory-phase-a.md](migration-inventory-phase-a.md) is current.
- This is a historical cutover sheet: Keycloak was retired in E4 after E3 closed
  with no clients. Do not expect a live Keycloak endpoint on the current platform.
- No change is applied by hand to the cluster. Service promotions follow
  [workflow.md](workflow.md#services-app-repo-as-source); platform changes land
  through reviewed PRs.

## Per-client migration sheet

Record one row per OIDC client before touching an environment:

| Field | Value |
| --- | --- |
| Service repository and `deploy/` path | — |
| Environment (`dev`/`qa`/`prod`) | — |
| Current issuer (`KC_HOSTNAME`) | `https://keycloak.local[:8443]/realms/sca` |
| Target issuer | `https://zitadel.local` |
| Client ID / secret location | Vault path or ExternalSecret in the service repo |
| Redirect URIs | Exact callback URLs used by the service |
| Grant / PKCE | Authorization Code + PKCE S256 where supported |
| Requested scopes | `openid`, `profile`, `email`, plus service-specific scopes |
| Required groups/roles | Keycloak realm role → Zitadel project role mapping |
| Owner and rollback contact | — |

Do not reuse a Keycloak client secret in Zitadel. Create the client in Zitadel,
store its secret in the service's existing Vault path, and let the service's
ExternalSecret project it.

## Cutover by environment

### `dev` and `qa`

1. In the service repository, update the OIDC issuer, client ID, secret
   reference, redirect URIs and role mapping to the Zitadel values.
2. Open a PR in the service repository and obtain the normal review.
3. After merge, run the service `promote` workflow against `dev`; it syncs the
   `<service>-dev` ArgoCD Application. Repeat for `qa` only after the `qa`
   approval gate.
4. Verify the service-specific OIDC flow using
   [Validation](#validation) below. Do not promote to `qa` with a failing
   `dev` check.

### `prod`

1. Merge the same service change to the service repository's `main` only after
   `dev` and `qa` are green.
2. Open the `chore(services)` PR that bumps the service's version tag pin in
   `argocd/services-prod.yaml`.
3. Treat that PR as the go/no-go gate. After merge, ArgoCD promotes the pinned
   version in `prod`.
4. Run [Validation](#validation) and keep the prior tag available for rollback.

## Validation

For each migrated client and environment:

- `curl https://zitadel.local/.well-known/openid-configuration` returns
  `"issuer":"https://zitadel.local"` and advertises
  `authorization_endpoint`, `token_endpoint` and `jwks_uri`.
- The service starts with no Keycloak issuer in its logs or configuration.
- An interactive login completes with PKCE S256 and the expected redirect URI.
- The resulting access token validates against Zitadel's `jwks_uri`, and the
  expected groups/roles are present.
- Service health checks and the platform smoke remain green:
  `make status` and `make smoke COMPONENT=zitadel`.
- Keycloak receives no new authentication traffic from the migrated client.

## Rollback

1. Revert the service promotion: re-sync the previous ArgoCD Application
   revision in `dev`/`qa`, or revert the version tag pin PR in `prod`.
2. Restore the service's previous Vault secret projection if the client secret
   was rotated; do not paste secrets into this repository.
3. If a legacy client absolutely must return to Keycloak, revert E4 first so the
   retired identity plane exists again, then re-run [Validation](#validation)
   against Keycloak and confirm the service is healthy.
4. Leave Zitadel running. Roll back the client only; do not tear down the new
   identity plane unless ADR-004 itself is reversed.

## Keycloak retirement gate (executed in E4)

E3 closed with no OIDC clients to migrate, so the retirement gate was executed by
ADR-004 E4. The platform PR:

- removed the `keycloak-<env>` Applications and their Makefile/CI wiring;
- removed the `keycloak-db` CNPG clusters, credentials and backup schedules;
- removed Keycloak TLS/realm manifests, Vault seeds/paths, smoke and catalog row;
- redirected the External Secrets smoke to `secret/postgres-app/<env>` and the
  CNPG latest-backup restore smoke to `zitadel-db`;
- updated `docs/status.md`, `docs/architecture.md`, `docs/roadmap.md`, this runbook
  and [ADR-004](adr/adr-004-keycloak-to-zitadel.md) in the same change.

There is no coexistence window after E4; Zitadel is the only issuer in the
platform catalog.
