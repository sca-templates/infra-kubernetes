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
  (the registry): `name`, `namespace`, `appRepo`, `wave`.
  `services-local.yaml` does **not** exist — `local` is the platform-only
  sandbox; services live from `dev` upward.
- Each `ApplicationSet` template pins the ref ArgoCD tracks:
  `deploy/dev` (dev), `deploy/qa` (qa), `main` (prod).
- The service namespace is created by ArgoCD (`CreateNamespace=true`); pick one
  per service (e.g. the service name).

Example registry element (all three files):

```yaml
- name: nest-authz
  namespace: nest-authz
  appRepo: https://github.com/sca-templates/nest-authz
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

## 4. Environment refs and promotion

Deployment is a **ref move**, not a PR in `infra-kubernetes`:

| Ref | Environment | Gate |
| --- | --- | --- |
| `deploy/dev` | dev (auto + prune) | none — last deployer wins |
| `deploy/qa` | qa (auto, no prune) | free, after a dev pass |
| `main` | prod (manual Sync in window) | PR merged after qa |

The service repo ships a `promote` GitHub Action (`workflow_dispatch` or on
merge to a `release/*` branch — the service owner's choice) that:

1. Builds and pushes the image with a unique tag (`sha-…` or semver; never
   `latest`).
2. Pins that tag in `deploy/values.yaml` (and any env override files).
3. Moves the refs ArgoCD tracks: `deploy/dev`, then `deploy/qa` on request.
4. Prod only via a PR to the service `main` **after** the change has passed
   dev and qa — the PR is the last step, not the first.

The repo rules must protect the refs and the PR path:

- `deploy/dev` and `deploy/qa` allow **force-push only from the bot** (the
  mechanism moves refs; humans do not push to them).
- `main` requires review + status checks (the service's own CI).
- Prod's Sync is manual (ADR-003), so a merge to `main` never auto-deploys prod.

Rollback on failure: point the env ref back at the previous known-good commit
(a no-op git move for dev/qa); for prod, revert the merge on the service `main`.

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

The service is now self-serve: it ships daily without touching
`infra-kubernetes` again unless its registration, namespace or secrets change.

## 6. Platform integration (once ready)

- Expose it behind Kong (Phase 8) so it is not reachable out-of-band.
- Add its `ServiceMonitor` to the radar set (Phase 14 design,
  [observability-radar.md](observability-radar.md)).
- Back it up with a Velero schedule/namespace label (Phase 18).
- There is nothing to update in this repo's catalog for a service — the
  service owns its manifest; the platform state pages list services in the
  registry only.
