# GitOps Workflow

How a change in `infra-kubernetes` becomes a deployment in an environment
cluster. Companion to [architecture.md](architecture.md) (the *state*) and
[ci-cd.md](ci-cd.md) (the *pipeline*).

## Mental model

- The repository is the single source of truth. Each environment cluster runs
  an ArgoCD that reconciles a root `Application` (`argocd/root-app-<env>.yaml`)
  from this repo; sync policies follow ADR-003.
- **Nothing is deployed by hand after `make bootstrap`.** A change becomes a
  deployment by landing in `main`; ArgoCD does the rest.
- One component = one commit, one PR, one review. A component that does not
  turn green **rolls back** (`git revert`-style), it is never patched forward
  with `fix` chains.

## Change → deploy flow

```mermaid
graph LR
    A[PR on main] --> B[CI: validate + security]
    B --> C[Human review]
    C --> D[Merge to main]
    D --> E[ArgoCD reconcile per env]
    E --> F[local: auto+prune] 
    E --> G[dev: auto+prune]
    E --> H[qa: auto, no prune]
    E --> I[prod: manual sync, go/no-go]
```

1. **Author**: edit only the files the change owns (component + its env
   overlays), run `make validate-static`, commit with a conventional message
   (`feat(vault): …`, `fix(kong): …`).
2. **CI**: static suite always; later phases add a *selective* cluster smoke of
   the touched component. See [ci-cd.md](ci-cd.md).
3. **Review**: a human reviews the diff; the reviewer is the gate for "turns
   green" (the per-component DoD in [status.md](status.md)).
4. **Merge**: ArgoCD picks it up per environment based on the sync policy.
   `prod` requires a human to press `Sync` in a deploy window.

## Environments and promotion

Advancing a component (or the whole stack) from one environment to the next is
a **promotion**, and it is always a separate PR that touches only that env's
`envs/<env>/` overlays plus `argocd/apps-<env>.yaml` (the registry).

| Env | Sync | Provenance of secrets | Notes |
| --- | --- | --- | --- |
| `local` | auto + prune | vault seeded via `bootstrap/seed-vault.sh` | kind; full catalog |
| `dev` | auto + prune | real Vault secrets | reduced HA |
| `qa` | auto, **no prune** | real Vault secrets | 3 replicas, PDBs, anti-affinity |
| `prod` | **manual** | real Vault secrets | full HA, real storage; human go/no-go in the deploy window |

**promote-test**: before promoting anything to `dev`/`qa`/`prod`, validate the
target env overlay on a local `kind` cluster loaded with
`ENV=dev|qa|prod` (`make bootstrap ENV=<env>` against the same overlay).
Promotion is only allowed when the promote-test passes and the component is
green in the lower environment.

## The escalation gate

If a component fails its gate (app not Healthy, pods crash-looping, smoke
red), the response is **rollback, not forward-churn**:

- Revert the offending commit (or the environment's view of it via the
  overlay), merge the revert, let ArgoCD reconcile it back.
- Investigate *why* it failed *before* attempting it again — never string
  `fix` commits onto a broken sync.
- Update [status.md](status.md) and the component's phase row to reflect the
  rollback; the doc records reality, not intent.

No ad-hoc `ignoreDifferences` patches, no `ServerSideApply=true` toggles, no
manual `kubectl apply` after bootstrap. If ArgoCD drift needs absorbing, it is
a deliberate, documented deviation (the [Deviations log](architecture.md#deviations-log)).

## Troubleshooting quick refs

| Symptom | Probable cause | Fix |
| --- | --- | --- |
| App `OutOfSync` | Drift or failed sync-wave | `kubectl get application <name> -n argocd`; inspect `status.conditions`; sync manually if prod |
| `SecretSyncedError` on an ExternalSecret | Vault path missing or k8s-auth role wrong | Check the `ClusterSecretStore` is Ready; verify `secret/<service>/<env>`; re-run `bootstrap/seed-vault.sh` (local) |
| Pods crash after a wave bump | Dependency started before its datastore/operator | Re-check wave assignment; consumers must be ≥10 above their dependency |
| ESO wedged (local) | Was running with the old long refresh pattern | Do **not** restart by hand; short refresh (~5 min) prevents recurrence |
| `ImagePullBackOff` | Bad pin or unreachable registry | Verify the pinned tag exists upstream; never float `latest` |
| kind cluster OOM | Host RAM exhausted | Stop sibling Compose stacks before bootstrapping; use the 1-replica local profile |
