# Pull Request — Phase <N> (<component>)

## Summary

<!-- One sentence: what and why. -->

## Phase reference

- `docs/roadmap.md` row: <!-- link or paste -->
- Local preview branch: <!-- branch name used for preview -->
- `targetRevision` reverted to `main` after gate: <!-- yes/no -->

## Changes

<!-- List files, components, environment impact. -->

## DoD gate evidence

<!-- Paste output of each command. Checkboxes mark completion. -->

- [ ] `make status` — no new Degraded
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

## Docs

- [ ] `docs/roadmap.md` Work Log row appended
- [ ] `docs/status.md` updated
- [ ] `docs/architecture.md` Status column flipped
- [ ] All four env overlays updated (or local-only documented)
- [ ] `README.md` / `AGENTS.md` updated if behavior changes

## Checklist

- [ ] Content in English
- [ ] No secrets, kubeconfigs, or generated artifacts
- [ ] Conventional commit (`feat(<scope>): ...`)
- [ ] Sync-waves respected (operators before CRs, Vault before ESO, datastores before consumers; new component wave >=10 apart)
- [ ] Security workflows green (gitleaks, checkov, pin guards)
- [ ] `CONTRIBUTING.md` read
