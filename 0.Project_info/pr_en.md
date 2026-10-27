# Pull Request Summary Generator

Generate a professional Pull Request by taking the repository's Pull Request template (`.github/pull_request_template.md`) and producing an **updated, completed version** based on the provided changes. This generator is wired to `merge.sh`, which injects the diff into `[[CHANGES]]`.

## Requirements
- **Title** must be a Conventional Commit summary (`feat(<scope>): ...`; ≤ 72 characters, no emojis). Squash-only merge makes this the commit message release-please reads.
- Analyze **carefully** to decide which checkboxes `[ ]` should be marked.
- Omit sections that do not apply (mark them `N/A` or remove the section).
- Do **not** include screenshots, demos, or reviewer mentions outside the generated content.

## Mandatory Structure

Mirror `.github/pull_request_template.md` exactly, in this order, and **update it**.

```markdown
# <type>(<scope>): <summary>

## Context
[What and why. Link the phase row or issue when one exists.]

## Type of change
- [ ] Phase delivery (P<N> / component)
- [ ] Bug fix (add a regression test when a suite covers the area)
- [ ] Docs / CI / chore (no runtime change)

## Phase reference (phase delivery only)
- `docs/roadmap.md` row: [link or paste]
- Local preview branch: [branch name used for preview]
- `targetRevision` reverted to `main` after gate: [yes/no]

## Changes
[List files, components, and environment impact.]

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
```

## Changes

```
[[CHANGES]]
```

## AI Instructions

1. **Treat `.github/pull_request_template.md` as the canonical template** and output an updated, fully completed version of it.
2. Generate **only** the Pull Request content, starting with the title.
3. Ensure the title is a short Conventional Commit (`feat(<scope>): ...`, ≤ 72 characters, no emojis), matching the `Type of change` you selected.
4. Analyze changes **thoroughly** to mark the correct checkboxes; mark only what the change actually covers.
5. **Fill or remove sections** as needed, using clear, concise professional English. Validation steps are not checklist items: local and CI validation are presupposed, so never add a "CI is green", "smoke passed" or "kubectl output" item.
6. Do not include explanations, screenshots, demos, or reviewer mentions outside the markdown.

**Generate ONLY the updated Pull Request content, starting with the title. Do not include extra explanations or formatting outside the markdown.**
