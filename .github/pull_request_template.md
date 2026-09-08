# Pull Request — <scope>

## Context

<!-- What and why. Link the phase row or issue when one exists. -->

## Type of change

- [ ] Phase delivery (P<N> / component)
- [ ] Bug fix (add a regression test when a suite covers the area)
- [ ] Docs / CI / chore (no runtime change)

## Phase reference (phase delivery only)

- `docs/roadmap.md` row: <!-- link or paste -->
- Local preview branch: <!-- branch name used for preview -->
- `targetRevision` reverted to `main` after gate: <!-- yes/no -->

## Changes

<!-- List files, components, environment impact. -->

## Validation

- [ ] `make validate-static` green
- [ ] Static CI green (gitleaks, checkov, pin guards, CodeQL, actionlint) — or N/A
- [ ] Smoke run for the changed component via `pr-cluster.yml` — or N/A
- [ ] Live cluster probes passed — or limitation documented

## DoD gate evidence (phase delivery only)

- [ ] `kubectl get applications -n argocd` — app Synced/Healthy
- [ ] `kubectl get pods -n <ns>` — pods Ready 2+ min
- [ ] `kubectl get externalsecret -A` — SecretSynced (if applicable)
- [ ] Functional smoke per-project gate

<details><summary>make status</summary>

```text
<paste output>
```

</details>

<details><summary>kubectl get applications</summary>

```text
<paste output>
```

</details>

<details><summary>kubectl get pods</summary>

```text
<paste output>
```

</details>

## Docs (updated when behavior or topology changes)

- [ ] `docs/roadmap.md` Work Log row appended
- [ ] `docs/status.md` updated
- [ ] `docs/architecture.md` Status column flipped
- [ ] All four `envs/<env>/<component>.yaml` overlays updated (or local-only documented)

## Checklist

- [ ] Content in English
- [ ] Commit(s) signed off with `git commit -s` (DCO)
- [ ] No secrets, kubeconfigs, or generated artifacts
- [ ] Conventional commit (`feat(<scope>): ...`)
- [ ] Sync-waves respected (operators before CRs, Vault before ESO, datastores before consumers; new component wave ≥10 apart)
- [ ] Security workflows green (gitleaks, checkov, pin guards) and CodeQL clean
- [ ] Rollback, not fix-chains: if the change fails its gate after merge, roll it back — no forward `fix` chains
- [ ] `CONTRIBUTING.md` read
