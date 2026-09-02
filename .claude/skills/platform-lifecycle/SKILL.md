---
name: platform-lifecycle
description: Bootstrap, validate and troubleshoot the sca Kubernetes platform (kind + ArgoCD app-of-apps). Use when the user asks to run prereqs/cluster-up/bootstrap/status/validate, add a component to the platform, inspect ArgoCD sync health, or fix OutOfSync apps, ExternalSecret failures or CrashLoopBackOff after a sync-wave change.
---

# Platform lifecycle

End-to-end bootstrap (local environment):

1. `make prereqs` — install pinned kubectl/helm/kind into `~/.local/bin` (idempotent).
2. `make cluster-up` — create the `kind` cluster from `bootstrap/kind-config.yaml`.
3. `make bootstrap` — install ArgoCD, then apply the root Application for
   `$ENV` (`argocd/root-app-${ENV}.yaml`). The root app renders the
   `ApplicationSet` for `$ENV` and ArgoCD syncs every component in
   sync-wave order. Watch with `make status`.

After bootstrap, changes deploy exclusively via `git push` — never
`kubectl apply` by hand. **Docs are the source of truth from Phase 1**: read
`docs/status.md` and `docs/architecture.md` before any platform work.

## How to add a component (checklist)

The docs define the target state — read them first:

1. Read `docs/architecture.md` (catalog, sync-waves, deviations log),
   `docs/roadmap.md` (the 18-phase plan + per-component gate) and
   `docs/onboarding-new-service.md` (add checklist). `docs/status.md` tells
   you what is actually deployed today.
2. Create `infrastructure/<name>/` with `README.md` (purpose, upstream chart,
   provenance links) and `values-base.yaml` (cross-env defaults).
3. Add per-env overlays: `envs/local/<name>.yaml`, `envs/dev/…`, `envs/qa/…`,
   `envs/prod/…` (all four, even if an empty-stub with a comment).
4. Add one element to the list generator of **every** `argocd/apps-<env>.yaml`
   that must run the component: `{ name, namespace, chartRepo, chart,
   targetRevision, wave, path }`.
5. Assign a `sync-wave` ≥10 apart from neighbors; operators/CRDs before CRs,
   Vault before ESO consumers, datastores before their consumers (see
   `docs/architecture.md`).
6. If it needs secrets: seed the Vault path `secret/<service>/<env>` in
   `bootstrap/seed-vault.sh` and add an `ExternalSecret` in the component dir.
7. Validate: `make validate-static`, then on a fresh kind cluster
   `make cluster-up && make bootstrap` and confirm the new Application is
   Synced/Healthy.
8. Update the docs in the **same commit**: append the roadmap Work Log row in
   `docs/roadmap.md`, flip the component's Status column to `deployed` in
   `docs/architecture.md`, and note any deviation. Docs are updated as
   components land; link the phase to its GitHub issue/milestone.

## Health checks (plain kubectl + helm mental model; no rollouts CLI)

- `kubectl get applications -n argocd` — every app `Synced` / `Healthy`.
- `kubectl get pods -A` — no `CrashLoopBackOff` / `ImagePullBackOff`.
- `kubectl get externalsecret -A` — every one `Ready` / `SecretSynced`.
- `helm list -A` — releases deployed at the pinned revisions.
- Per component: `kubectl -n <ns> get pods` and the component table in
  `docs/architecture.md` for namespaces.

## Troubleshooting

Mirrors `AGENTS.md` §9 and `docs/workflow.md`:

- App `OutOfSync`: drift or failed wave — inspect
  `kubectl get application <name> -n argocd -o yaml` `status.conditions`;
  sync manually only for prod-style flows.
- ExternalSecret `SecretSyncedError`: Vault path or kubernetes-auth role —
  check `ClusterSecretStore vault` Ready, verify the path under
  `secret/<service>/<env>`, re-run `bootstrap/seed-vault.sh` (local).
- `CrashLoopBackOff` after a wave bump: dependency ordering — consumers must
  be ≥10 above their datastore/operator.
- kind OOM: stop the Docker Compose stack first; the `local` profile is
  1-replica minimal by design.
- `ImagePullBackOff`: bad pin or unreachable registry — verify the tag exists
  upstream; never float `latest`.
- ESO wedge (local): do **not** restart ESO by hand; the short
  `refreshInterval` (~5 min) prevents the wedge.

## Armor rules (verbatim)

- **One phase/component = one commit = one PR = one review.** A component that
  does not turn green **rolls back** — no `fix` chains, no ad-hoc
  `ignoreDifferences`/SSA patches.
- **No global `ServerSideApply`.** Kong runs as a dedicated Application with no
  SSA.
- **ESO uses a short (`~5 min`) `refreshInterval` in local** — never restart
  ESO by hand.
- **Nothing is deployed by hand after `make bootstrap`** — never `kubectl
  apply` by hand.
