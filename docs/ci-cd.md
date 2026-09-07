# CI/CD

What GitHub Actions do — and deliberately do **not** — do for this
repository. Phase 0 ships the static workflows plus the release automation
(no cluster smoke); **Phase 1 ships the cluster-smoke workflow
(`pr-cluster.yml`)**, rebuilt from scratch and run on an ephemeral `kind`
cluster. See [security.md](security.md) for the security controls these
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
| Release gate | `.github/workflows/release-gate.yml` | PR + manual | blocks human PRs while a release-please PR is open (`release-gate` required check) |

### Scope semantics

- `validate.yml` runs the same checks locally via `make validate-static`
  (`bootstrap/sca.sh` installs the pinned CLI; no cluster required).
- `security.yml` guards run against the whole tree on every PR; the checkov
  **baseline** (`.github/checkov-baseline.json`) gates new findings — existing
  entries are documented, intentional manifests (see
  [security.md](security.md)).
- Workflows are scoped to the paths they own (docs/CI config), so a pure
  documentation PR does not re-run IaC scanning unnecessarily.

## Local toolchain CLI

`bootstrap/sca.sh` is the POSIX platform CLI (Linux distro-agnostic, macOS and
WSL2; Windows-native fails fast — use WSL2). The Makefile targets are thin
wrappers around it; `make install-cli` symlinks it as `~/.local/bin/sca`.

| Command | What it does |
| --- | --- |
| `sca prereqs` | Install pinned kubectl/helm/kind into `~/.local/bin` — idempotent, sha256-verified, no sudo. Detects OS/arch (linux/darwin, amd64/arm64) and picks the matching upstream URLs; external deps (git, docker) are reported with install hints but never installed |
| `sca doctor` | Read-only health: toolchain versions vs pins, PATH, docker, git, git source reachability, cluster, ArgoCD app sync/health, and the `.env` seam. Never mutates — run it first when something is off |
| `sca version` | Print the pinned toolchain versions |

Versions are pinned once in `bootstrap/versions.sh` (sourced by `sca.sh`);
`.env`/environment overrides still win. The darwin install path follows the
upstream URL patterns but is not yet exercised on hardware — see the pin
guards in [security.md](security.md).

### Release workflow

`release.yml` has two jobs:

- **release-please** — computes the next version, opens or updates the release
  PR, and on merge creates the tag and the GitHub Release.
- **sign-tag** — re-creates the tag as an annotated tag signed by the
  release-bot GPG key on the same commit. It runs on every release **or** on a
  manual `workflow_dispatch` (`tag_name` + `commit_sha`), which is how an
  already-published lightweight tag is promoted to signed (used for `v0.1.0`).

The workflow is the only one that holds repository secrets
(`APP_ID`, `APP_PRIVATE_KEY`, `RELEASE_GPG_PRIVATE_KEY`) — see
[secrets.md](secrets.md) for how they are stored and rotated.
`release-please` and the tag push authenticate as the org-owned
`sca-bot-release` GitHub App via a per-run installation token minted with
`actions/create-github-app-token` (scoped to `infra-kubernetes`), so release
PRs/tags are authored by `sca-bot-release[bot]` and still trigger the required
checks.

## Cluster smoke (`pr-cluster.yml`, Phase 1)

`pr-cluster.yml` is **absent** from Phase 0 because the previous attempt's
cluster-smoke CI had become a stack of hacks (trimmed manifests, self-heal
disabled) and burned a week in `fix` churn. It lands at **Phase 1** with
cert-manager, so each subsequent component is validated incrementally in a
live `kind` cluster as it ships, and the deployed baseline is continuously
monitored. See the [roadmap](roadmap.md) for the Phase 1 gate and its smoke.

**Triggers:**

- **`pull_request`** — selective smoke of the touched component (profile
  `local`), so a change is validated before it merges. Same-repo PRs only
  (fork PRs are skipped, coherent with `main-sync.yml`).
- **`push` to `main`** — vigilance smoke of the deployed baseline
  (`cert-manager`, `REF=main`), confirming the platform keeps working as
  components land. This is the "is it still healthy" guard.

The whole boot → apply → wait → run → diagnose → teardown cycle lives in
`bootstrap/smoke-ci.sh`; each component adds only its own smoke command
(`bootstrap/smoke-<component>.sh`, dispatched by `smoke-target.sh`).

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
- **Merge gate**: the smoke runs as an **informative** check — it is not a
  required check until stable on 2–3 components. Making it blocking is a
  branch-protection change on `main` (add `pr-cluster` to the required checks
  for the paths it covers), **not** a change to this file. Until then a failed
  smoke reports but does not block a human merge; once stable it becomes a
  required check, so infra-only doc changes are not blocked by a cluster boot.

### Release gate

`release-gate.yml` runs on every PR and holds a single fact: **a
release-please PR (head branch `release-please--branches--main` against the
default branch) must merge before any human PR**. While one is open, human
PRs keep a failing `release-gate` check (`::error` and non-zero exit) and
cannot merge; the release PR is excluded (only release-please opens that
branch, and only one exists at a time), so it is never blocked. Because the
check is registered as a required context on `main`, the block is enforced by
branch protection, not by policy. The gate keys on the *branch name* of the
release PR — which only release-please can produce — matching the
[main-sync](workflow.md#queued-prs-branch-names-and-main-sync) model where
mechanisms trust the reserved branch, never ad-hoc PR titles.

## Required checks

Enforce, on `main`:

1. `Validate` (static) — required on every PR.
2. `Security` — required on every PR (block on gitleaks findings).
3. `CodeQL` — required once stable.
4. `release-gate` — required on every PR (fails while a release PR is open;
   passes on the release PR itself).
5. Human review — always the release gate for "turns green".

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
