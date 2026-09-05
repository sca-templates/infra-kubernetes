# CI/CD

What GitHub Actions do — and deliberately do **not** — do for this
repository. Phase 0 ships the static workflows plus the release automation
(still **no** cluster smoke); the cluster-smoke workflow (`pr-cluster.yml`)
**returns at Phase 1**, when the first real component lands, and is rebuilt
from scratch. See [security.md](security.md) for the security controls these
workflows carry, [versioning.md](versioning.md) for how releases, tags and the
CHANGELOG are produced, and [workflow.md](workflow.md) for how a merge becomes
a deployment.

## Shipped workflows

| Workflow | File | Runs on | What it does |
| --- | --- | --- | --- |
| Validate | `.github/workflows/validate.yml` | push + PR | Static suite: markdownlint, yamllint, YAML parse, `bash -n`, actionlint (workflow lint), kube-linter (K8s manifest lint) |
| Security | `.github/workflows/security.yml` | push + PR | gitleaks, checkov (static IaC), osv-scanner (SCA), pin guards (no `latest` tags/charts) |
| CodeQL | `.github/workflows/codeql.yml` | push + PR + schedule | GitHub CodeQL static analysis on the repo languages |
| Scorecard | `.github/workflows/scorecard.yml` | push + schedule | OpenSSF Scorecard attestation + badge |
| Release | `.github/workflows/release.yml` | push to `main` | release-please opens release PRs, tags (+ signed annotated tags) and GitHub Releases; drives `CHANGELOG.md`; a manual `workflow_dispatch` (`tag_name` + `commit_sha`) re-signs an existing tag (see [versioning.md](versioning.md)) |

### Scope semantics

- `validate.yml` runs the same checks locally via `make validate-static`
  (`bootstrap/prereqs.sh` installs the pinned CLI; no cluster required).
- `security.yml` guards run against the whole tree on every PR; the checkov
  **baseline** is re-examined before it is enforced (see
  [security.md](security.md)).
- Workflows are scoped to the paths they own (docs/CI config), so a pure
  documentation PR does not re-run IaC scanning unnecessarily.

### Release workflow

`release.yml` has two jobs:

- **release-please** — computes the next version, opens or updates the release
  PR, and on merge creates the tag and the GitHub Release.
- **sign-tag** — re-creates the tag as an annotated tag signed by the
  release-bot GPG key on the same commit. It runs on every release **or** on a
  manual `workflow_dispatch` (`tag_name` + `commit_sha`), which is how an
  already-published lightweight tag is promoted to signed (used for `v0.1.0`).

The workflow is the only one that holds repository secrets
(`RELEASE_PLEASE_TOKEN`, `RELEASE_GPG_PRIVATE_KEY`) — see
[secrets.md](secrets.md) for how they are stored and rotated.

## Cluster smoke (`pr-cluster.yml`, returns at Phase 1)

`pr-cluster.yml` is **deliberately absent** from Phase 0: the previous
attempt's cluster-smoke CI had become a stack of hacks (trimmed manifests,
self-heal disabled) and burned a week in `fix` churn. It **returns at Phase 1**,
when cert-manager (the first real component) lands, so each subsequent
component is validated incrementally in a live `kind` cluster as it ships.
See the [roadmap](roadmap.md) for the Phase 1 gate and its smoke.

### Design properties

- **Selective**: boots an ephemeral `kind` cluster and smokes *only* the
  component the PR touches (plus any already-shipped dependency it needs), not
  the whole platform. A docs-only PR skips the cluster entirely.
- **No trim hacks**: the smoke runs the real chart/CR, not a reduced copy.
- **No self-heal disabling**: ArgoCD auto-reconcile stays on during the smoke;
  the component is applied via its ArgoCD `Application`, letting ArgoCD converge
  and reconcile on its own.
- **Incremental, not accumulative**: each smoke validates the touched component
  against an already-converged cluster; the framework (boot, apply, wait,
  diagnose, teardown) is shared and only the component-specific smoke command is
  added per phase.

### Environment profile: `local` (not `qa`)

The smoke runs the **`local`** profile (1 replica, auto-sync + prune), never
`qa`. This is a deliberate decision on resources and security:

| Criterion | `local` (1 replica, auto+prune) | `qa` (3 replicas, PDB, anti-affinity, no-prune) |
| --- | --- | --- |
| Fits a CI runner (2 vCPU / 7 GB kind) | Yes | No — HA (3 replicas + anti-affinity) overflows it / OOM |
| Converges within the wait timeout (~5 min) | Yes | Slower; risks false-fail timeouts |
| Actually exercises HA / anti-affinity | — | **No**: a 1-node kind cannot; validating "HA" there is false confidence |
| Reproducible between PRs | Prune → clean, identical state each run | `no-prune` → residual state accumulates |
| What it proves | "applies and works (local)" | "resists HA" — that is `promote-test`'s job, on real envs |

- **Security**: the smoke is an **ephemeral, isolated** `kind` cluster that is
  torn down after every run; it never touches `qa`/`prod`. The real security
  boundary is the runner's minimal scope (`permissions: contents: read`, no
  injected real kubeconfigs/secrets) — not the replica count.
- **Promotion stays separate**: the jump to real HA (`dev`/`qa`/`prod`) is
  gated by `promote-test` ([workflow.md](workflow.md)), which loads the target
  env overlay on a local `kind` cluster. The smoke validates correctness;
  `promote-test` validates the env overlay against a real protectable surface.
- **Merge gate remains**: until the smoke is stable on 2–3 components it runs
  as an **informative** check, not blocking; it becomes a required check only
  for the paths it covers once stable, so infra-only doc changes are not
  blocked by a cluster boot.

## Required checks

Enforce, on `main`:

1. `Validate` (static) — required on every PR.
2. `Security` — required on every PR (block on gitleaks findings).
3. `CodeQL` — required once stable.
4. Human review — always the release gate for "turns green".

The two `Validate` linters and the `Security` SCA job are part of the required
`Validate`/`Security` checks above, so a clear PR must satisfy Markdown +
YAML + shell + workflow lint, kube-linter, gitleaks, checkov and osv-scanner
before merge.

## Local parity

Everything CI runs statically can be reproduced locally:

```bash
make validate-static     # markdownlint, yamllint, YAML parse, bash -n
make validate            # static + live cluster checks (needs cluster-up)
```

yamllint runs locally only if installed; CI always runs it.
