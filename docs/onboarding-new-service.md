# Onboarding a New Service

The contract for a microservice (e.g. `nest-authz`) on the platform. A service
is **app-repo-as-source**: it owns its Kubernetes manifests in its own
repository (`deploy/`) and reaches each environment through refs that
`infra-kubernetes` points ArgoCD at. This page is the per-service **add
checklist**; the deployment model it implements is in
[workflow.md](workflow.md#services-app-repo-as-source).

> This is **not** the catalog flow. Platform components (Vault, Kong, …) are
> centralized in `infrastructure/<component>/` and follow the checklist in
> [roadmap.md](roadmap.md). Services are self-owned.

## 0. The repo

A service lives in its own repository under `sca-templates` (e.g.
`sca-templates/nest-authz`). The platform registers it by pointing an
`Application` at that repo — it expects a `deploy/` directory shaped like a Helm
chart. `charts/service-template/` in this repo is the canonical seed: copy it
into the service repo as `deploy/` and rename.

## 1. Scaffold `deploy/` from the template

Copy `charts/service-template/` to `deploy/` in the service repo:

```bash
cp -r charts/service-template deploy
```

Customize:

- `Chart.yaml` — `name` (must match the registry entry), `version`,
  upstream image pinned by **version** in `values.yaml` (`none`/`latest` fail
  the pin guards and are policy violations). This repo builds **no images**;
  the service repo builds and publishes its own.
- `templates/` — keep only what the service uses (`configmap.yaml`,
  `externalsecret.yaml`, `hpa.yaml`, `ingress.yaml`, `pdb.yaml`,
  `servicemonitor.yaml` are optional).
- `values.schema.json` — keep in sync.
- Delete `templates/` files the chart does not use; keep the
  `values.env/*` convention below.

The chart must render **per environment** from `env/<env>.yaml` files because
each environment's `Application` selects its own value file:

- `deploy/values.yaml` — shared defaults and the **pinned image tag**.
- `deploy/env/dev.yaml` — dev overrides (usually `replicaCount: 1`).
- `deploy/env/qa.yaml` — qa overrides (3 replicas, PDBs, anti-affinity).
- `deploy/env/prod.yaml` — prod overrides (full HA, real storage).

ArgoCD applies them via `helm.valueFiles` in the services `ApplicationSet`
(`argocd/services-<env>.yaml`), so the per-env values **must** live at
`env/<env>.yaml` relative to the chart root.

## 2. Register the service per environment

- Add one element to `argocd/services-<env>.yaml` for `dev`, `qa` and `prod`
  (the registry): `name`, `namespace`, `appRepo`, `wave`. Prod's element
  **additionally** carries `version` — the tag prod tracks (the template reads
  it with `missingkey=error`, so every prod element must set it).
  `services-local.yaml` does **not** exist — `local` is the platform-only
  sandbox; services live from `dev` upward.
- Each `ApplicationSet` template pins what ArgoCD tracks per env:
  `deploy/dev` (dev), `deploy/qa` (qa), `version` (prod).
- The service namespace is created by ArgoCD (`CreateNamespace=true`); pick one
  per service (e.g. the service name).

Example registry elements:

```yaml
# argocd/services-dev.yaml and services-qa.yaml
- name: nest-authz
  namespace: nest-authz
  appRepo: https://github.com/sca-templates/nest-authz
  wave: "60"

# argocd/services-prod.yaml — version is required
- name: nest-authz
  namespace: nest-authz
  appRepo: https://github.com/sca-templates/nest-authz
  version: v1.2.0
  wave: "60"
```

## 3. Wire secrets (if any)

The secret flow is unchanged from [secrets.md](secrets.md):

1. Add the path to the seed plan (`secret/<service>/<env>`).
2. One `ExternalSecret` → `ClusterSecretStore vault` in the service `deploy/`
   (`externalSecret.enabled: true`, `secretStoreRef: {name: vault, kind:
   ClusterSecretStore}`).
3. Pods mount the projected `Secret`; the raw value never appears in the
   manifest.

## 4. Environment refs, releases and promotion to prod

Dev/qa deployment is a **ref move**; prod deployment is a **version pin**:

| Ref / pin | Environment | Gate |
| --- | --- | --- |
| `deploy/dev` | dev (auto + prune) | none — last deployer wins |
| `deploy/qa` | qa (auto, no prune) | free, after a dev pass |
| `version` tag in `argocd/services-prod.yaml` | prod (manual Sync in window) | reviewed `chore(services)` bump + go/no-go |

The service repo ships two `workflow_dispatch` wrappers copied from
CI-CD-Templates' `docs/examples/` (`promote.yml`, `deploy-prod.yml`):

- `promote.yml` — builds and pushes the image with a unique tag (`sha-…`; never
  `latest`) and moves the refs ArgoCD tracks: `deploy/dev`, then `deploy/qa` on
  request (dev promotes immediately; `qa` waits for an approval when the repo's
  `qa` GitHub Environment has **Required reviewers** configured — **public
  repos** on Free/Pro/Team, Enterprise Cloud required for private ones).
- `deploy-prod.yml` — the two manual prod steps:
  - `action: adopt` opens the `chore(services)` bump PR (below);
  - `action: mark-latest` corrects GitHub `latest` after the prod `Sync`.

Reaching prod is a **version-gated** flow (releases happen upstream in the
service repo, the adopt-bump lands here):

1. The service opens the feature PR to its `main` **after** dev and qa passed
   ([workflow.md](workflow.md#services-app-repo-as-source)) — the only code PR.
2. On merge, release-please (in the service repo) opens a release PR the bot
   **auto-merges**, cutting the immutable signed tag `vX.Y.Z`.
3. A human runs `deploy-prod` with `action: adopt` and the `release-tag`; the
   wrapper calls `shared-adopt-prod.yml`, which opens the
   `chore(services): adopt nest-authz vX.Y.Z` PR bumping the `version` pin in
   `argocd/services-prod.yaml`. Because the commit type is `chore`, **no** infra
   release PR opens ([versioning.md](versioning.md)).
4. Human review of the bump is the **go/no-go**; on merge the prod
   `Application` goes `OutOfSync` and the human `Sync` in the deploy window
   applies it. Once prod is running that version, a human runs `deploy-prod`
   with `action: mark-latest` so `latest` = `vX.Y.Z` on the service repo.

So the flow has **2 human gates**: the feature PR (code review) and the
`chore(services)` bump (go/no-go) — plus the manual prod `Sync`. Release PRs
are bot-managed; the adopt and mark-latest steps are invoked from the service's
`deploy-prod` workflow.

The repo rules must protect the refs and the PR path:

- `deploy/dev` and `deploy/qa` allow **force-push only from the bot** (the
  mechanism moves refs; humans do not push to them). Apply CI-CD-Templates'
  `service-deploy-refs` ruleset with **higher precedence** than any
  `allowed-branches-only` ruleset, so the bot's force-push is allowed.
- `main` requires review + status checks (the service's own CI).
- Prod's Sync is manual (ADR-003), so a bump merge never auto-deploys prod.

Rollback on failure: point the env ref back at the previous known-good commit
(a no-op git move for dev/qa); for prod, revert the `chore(services)` bump so
the pin returns to the previous version tag.

## 5. Gates (per-service DoD)

Onboarding is complete when:

- Chart renders and applies; `Application <name>-dev|qa|prod` `Synced` +
  `Healthy`.
- Pods `Running` — no `CrashLoopBackOff`/`ImagePullBackOff` after 2+ min.
- `ExternalSecret` → `SecretSynced` where applicable.
- The service's own CI validates the change before `deploy/<env>` refs move
  (unit tests, image build, optional smoke).
- Env refs actually deploy: the dev deploy proves the ref move → sync path
  works end to end.

The service is now self-serve: dev/qa ship without touching `infra-kubernetes`;
prod ships by running the service's `deploy-prod` workflow (`action: adopt`)
and reviewing/merging its per-version bump PR, then `Sync`ing prod.
Registration, namespace or secrets changes still touch the registry.

## 6. Platform integration (once ready)

- Expose it behind Kong (Phase 8) so it is not reachable out-of-band.
- Add its `ServiceMonitor` to the radar set (Phase 14 design,
  [observability-radar.md](observability-radar.md)).
- Back it up with a Velero schedule/namespace label (Phase 18).
- There is nothing to update in this repo's catalog for a service — the
  service owns its manifest; the platform state pages list services in the
  registry only.
