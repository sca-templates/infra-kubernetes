# <type>(<scope>): <summary>

<!-- Squash-only merge means this title becomes the commit message release-please reads. -->

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

## Docs (updated when behavior or topology changes)

- [ ] `docs/roadmap.md` Work Log row appended
- [ ] `docs/status.md` updated
- [ ] `docs/architecture.md` Status column flipped
- [ ] All four `envs/<env>/<component>.yaml` overlays updated (or local-only documented)

## Checklist

- [ ] Content in English
- [ ] Commit(s) signed off with `git commit -s` (DCO)
- [ ] Conventional commit (`feat(<scope>): ...`) matching the selected type
- [ ] No secrets, kubeconfigs, or generated artifacts
- [ ] Sync-waves respected (operators before CRs, Vault before ESO, datastores before consumers; new component wave ≥10 apart)
- [ ] Rollback, not fix-chains: if the change fails its gate after merge, roll it back — no forward `fix` chains
- [ ] `.github/CONTRIBUTING.md` read
