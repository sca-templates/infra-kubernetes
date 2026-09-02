# CI/CD

What GitHub Actions do — and deliberately do **not** — do for this
repository. Phase 0.0 ships four workflows; the cluster-smoke workflow returns
in later phases, rebuilt from scratch. See [security.md](security.md) for the
security controls these workflows carry, and [workflow.md](workflow.md) for
how a merge becomes a deployment.

## Shipped workflows

| Workflow | File | Runs on | What it does |
| --- | --- | --- | --- |
| Validate | `.github/workflows/validate.yml` | push + PR | Static suite: markdownlint, yamllint, YAML parse, `bash -n` (mirrors `make validate-static`) |
| Security | `.github/workflows/security.yml` | push + PR | gitleaks, checkov (static IaC), pin guards (no `latest` tags/charts) |
| CodeQL | `.github/workflows/codeql.yml` | push + PR + schedule | GitHub CodeQL static analysis on the repo languages |
| Scorecard | `.github/workflows/scorecard.yml` | push + schedule | OpenSSF Scorecard attestation + badge |

### Scope semantics

- `validate.yml` runs the same checks locally via `make validate-static`
  (`bootstrap/prereqs.sh` installs the pinned CLI; no cluster required).
- `security.yml` guards run against the whole tree on every PR; the checkov
  **baseline** is re-examined before it is enforced (see
  [security.md](security.md)).
- Workflows are scoped to the paths they own (docs/CI config), so a pure
  documentation PR does not re-run IaC scanning unnecessarily.

## Cluster smoke (planned, not shipped)

`pr-cluster.yml` is **deliberately absent** from Phase 0.0/0.1. The previous
attempt's cluster-smoke CI had become a stack of hacks (trimmed manifests,
self-heal disabled) and burned a week in `fix` churn. It returns in later
phases, rebuilt from scratch with these properties:

- **Selective**: boots an ephemeral `kind` cluster and smokes *only* the
  component the PR touches, not the whole platform.
- **No trim hacks**: the smoke runs the real chart/CR, not a reduced copy.
- **No self-heal disabling**: ArgoCD auto-reconcile stays on during the smoke.

Until it returns, the merge gate is static validation + human review
(workflow.md's escalation gate).

## Required checks

Enforce, on `main`:

1. `Validate` (static) — required on every PR.
2. `Security` — required on every PR (block on gitleaks findings).
3. `CodeQL` — required once stable.
4. Human review — always the release gate for "turns green".

When the cluster smoke returns, add it as a required check only for the paths
it covers, so infra-only docs changes are not blocked by it.

## Local parity

Everything CI runs statically can be reproduced locally:

```bash
make validate-static     # markdownlint, yamllint, YAML parse, bash -n
make validate            # static + live cluster checks (needs cluster-up)
```

yamllint runs locally only if installed; CI always runs it.
