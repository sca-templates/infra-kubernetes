# Project: Implement Keycloak

Area: Security & Identity · Wave 50 · Environments: local→dev→qa→prod
Depends on: postgres-app/keycloak-db (#15) — its database; cert-manager (#6) for TLS.
Project done when: Keycloak pod `Running`; realm `sca` exists with a test client;
login/redirect works over TLS.

## Milestone M1 — Deploy

M1 done when: pod `Running`, app `Synced`/`Healthy`.

- [x] Issue #18 · Deploy `codecentric/keycloakx` (+ realm `sca`)
  Depends on: postgres-app/keycloak-db (#15), cert-manager (#6)
  - [x] `infrastructure/keycloak/` values-base + overlays for 4 envs
        - [x] envs/local, dev, qa, prod
        - Commits: `feat(keycloak): add chart reference and per-env overlays`
  - [x] DB connection to `keycloak-db` (CNPG), not in-cluster H2
        Commits: `feat(keycloak): external database connection`
  - [x] realm `sca` + test client + user
        Commits: `feat(keycloak): sca realm and test client`
  - [x] smoke: login → redirect roundtrip over TLS
        Commits: `test(keycloak): login and redirect smoke`
  - [x] docs: Work Log row + catalog Status → deployed
        Commits: `docs(keycloak): mark deployed`
  Issue done when: realm `sca` is imported and the smoke token works through the TLS edge.

No natural further phases → issues stay under M1.

## Implementation notes

- Chart pin: `codecentric/keycloakx` `7.4.0` with
  `quay.io/keycloak/keycloak:26.8.1`; the `bitnami/keycloak` row in the
  original plan was stale — that chart is no longer a viable pin.
- Dedicated multi-source `Application` per environment
  (`argocd/keycloak-<env>.yaml`, wave 50): chart + `$values` + per-env
  ExternalSecrets + shared realm/TLS manifests. It is not in the platform
  `ApplicationSet` because it owns both a Helm release and raw resources.
- Realm import is declarative: `ConfigMap keycloak-realm-sca` mounts
  `sca-realm.json` and `--import-realm` imports it on first start. The
  `sca-smoke` public client uses PKCE S256 and direct grants for the smoke;
  the `smoke` user password is resolved from the `keycloak-test-user` Secret.
- `keycloak-db-credentials`, `keycloak-admin` and `keycloak-test-user` are
  projected by ESO from `secret/keycloak-db/<env>`, `secret/keycloak/admin` and
  `secret/keycloak/test-user/<env>`.
- The edge certificate (`keycloak-tls`) is issued by the `sca-ca`
  `ClusterIssuer`; Kong serves Keycloak at `https://keycloak.local` (local:
  `:8443`).
- Bootstrap-only values: `KC_BOOTSTRAP_ADMIN_*` and the realm import are
  applied on first start; rotating the Vault values later (even with
  `SEED_ROTATE=1`) updates the projected Secrets but not Keycloak. Rotate
  those credentials through the Admin API (or recreate/import the realm).
- Smoke (`make smoke COMPONENT=keycloak`): StatefulSet Ready, all three
  ExternalSecrets `SecretSynced`, realm imported, TLS certificate Ready,
  discovery issuer matches `KC_HOSTNAME`, a PKCE S256 `prompt=none` request
  returns a `login_required` redirect, and the smoke user obtains a token
  accepted by userinfo.
