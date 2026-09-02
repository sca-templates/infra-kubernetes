# Plan: Phase 0.3 — GitHub community templates

## Context

This plan adds the full GitHub-facing surface (issue templates, discussion templates, PR template, CONTRIBUTING.md, CODEOWNERS, SUPPORT.md) to the `infra-kubernetes` repository before the first `git push`. All content reflects v2 workflow: phases and roadmap as source of truth, DoD gates, environment gradient, armor rules, and the preview-over-branch technique.

## Pre-conditions

- Phase 0.2 (tooling/git) completed.
- GitHub handle resolved: **@Santiago1010**.
- No existing `.github/ISSUE_TEMPLATE/` or `.github/DISCUSSION_TEMPLATE/` directories.
- `SECURITY.md` exists at repo root.
- `make validate-static` runs: `markdownlint-cli2` (all `*.md`), `js-yaml` (all `*.yaml`/`*.yml`), `yamllint`, `bash -n`.

## Files to create/edit

### A. `.github/ISSUE_TEMPLATE/config.yml`

```yaml
blank_issues_enabled: false
contact_links:
  - name: 💬 Ask in Discussions
    url: https://github.com/sca-templates/infra-kubernetes/discussions/categories/q-a
    about: Questions about the platform, how to use it, or troubleshooting
  - name: 🔒 Report a security vulnerability
    url: https://github.com/sca-templates/infra-kubernetes/security/advisories/new
    about: Report security vulnerabilities privately (do not open a public issue)
```

### B. `.github/ISSUE_TEMPLATE/bug_report.yml`

Issue form with YAML `body`. Fields:

- `name: Bug report`
- `description: Report a problem with the platform or a component`
- `title: "bug: [component] <short description>"`
- `labels: ["bug"]`
- `body`:

  - dropdown `Environment`: local / dev / qa / prod / unsure (required)
  - input `Phase or component`: e.g. "P2 Vault", "Kong", "CI" (required)
  - dropdown `Symptom`: OutOfSync / SecretSyncedError / CrashLoopBackOff / ImagePullBackOff / webhook or admission / other (required)
  - textarea `Expected behavior` (required)
  - textarea `Actual behavior` (required)
  - textarea `Evidence`: suggest `make status`, `kubectl get applications -n argocd`, `kubectl get externalsecret -A`, `kubectl describe pod -n <ns> <pod>` (required)
  - checkboxes: "I read AGENTS.md §Troubleshooting first", "Reproducible on a fresh `local` cluster (or why not)"

### C. `.github/ISSUE_TEMPLATE/feature_request.yml`

Issue form. Fields:

- `name: Feature request`
- `title: "feat: ..."`
- `labels: ["feature"]`
- `body`:

  - dropdown `Area`: new component / phase change / CI / docs / process / other (required)
  - textarea `Problem` (required)
  - textarea `Proposed behavior`
  - textarea `Alternatives`
  - textarea `Acceptance criteria`
  - input `Roadmap impact`: which phase row(s) in `docs/roadmap.md` it touches (required)

### D. `.github/ISSUE_TEMPLATE/phase_task.yml`

Issue form to track ONE roadmap phase. Fields:

- `name: Phase / component addition`
- `title: "phase: P<N> <component>"`
- `labels: ["phase"]`
- `body`:
  - input `Phase row (docs/roadmap.md)` (required)
  - input `Namespace / wave / gate` (required)
  - dropdown `Registration`: local only / local + promote dev / dev+qa+prod (required)
  - checkboxes `Implementation` (all required):
    - `infrastructure/<c>/ README + values-base`
    - `manifests`
    - `envs/{local,dev,qa,prod}/<c>.yaml`
    - `appset element`
    - `sync-wave respected`
    - `seed-vault entry if secrets needed`
    - `docs updated`
  - checkboxes `Definition of Done` (all required):
    - `app Synced/Healthy`
    - `pods Ready 2+ min`
    - `ExternalSecret SecretSynced (if applicable)`
    - `functional smoke`
    - `validate-static green`
    - `roadmap Work Log row appended`

### E. `.github/pull_request_template.md` (rewrite)

Restructured for v2:

````markdown
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
- [ ] Sync-waves respected (operators before CRs, Vault before ESO, datastores before consumers; new component wave ≥10 apart)
- [ ] Security workflows green (gitleaks, checkov, pin guards)
- [ ] `CONTRIBUTING.md` read

````

### F. `.github/CONTRIBUTING.md` (rewrite)

Adapt the reference, emphasizing v2:

1. **Ground Rules** — English, no secrets, no manual deployment, conventional commits.
2. **Roadmap is source of truth** — read `docs/roadmap.md` for current phase; every change is a phase/PR with a DoD gate.
3. **Preview-over-branch technique** — create a branch for preview, revert `targetRevision` to `main` after gate passes.
4. **Rollback-not-fix-chains** — if a component doesn't turn green, roll back; no fix chains, no ad-hoc patches.
5. **Making Changes** — read `AGENTS.md` and `docs/` first; update all four env overlays; respect sync-waves; run `make validate-static`; CI enforces secrets/IaC/pinning.
6. **Adding a Component** — follow `docs/onboarding-new-service.md` and the phase template checklist.
7. **Definition of Done** — English, no secrets, env overlays, sync-waves, validate-static green, docs updated.
8. **Questions & Issues** — questions go to Discussions (Q&A); bugs use `bug_report.yml`; features use `feature_request.yml`; phase tasks use `phase_task.yml`.
9. **Environment gradient** — local lightest → prod unlimited; qa mirrors prod with minimum resources.

### G. `.github/DISCUSSION_TEMPLATE/` (create)

Four plain markdown files:

- `announcements.md` — Title / date / scope & impact / rollout steps / rollback.
- `ideas.md` — Idea, motivation, affected components/phases, sketch, open questions.
- `q-a.md` — Question, context, what I already read in docs/, what I tried.
- `general.md` — Topic, context.

### H. `CODEOWNERS` (repo root)

```text
* @Santiago1010
```

### I. `SUPPORT.md` (repo root)

Short page: where to get help (Discussions → Q&A), how to report bugs (`bug_report.yml`), how to propose features and phase tasks, vulnerability handling (SECURITY.md). State: no SLA, maintainer-driven, best-effort. Link relative paths.

## Execution sequence

1. Read docs (already done: INDEX.md, roadmap.md, onboarding-new-service.md, AGENTS.md).
2. Create directories: `.github/ISSUE_TEMPLATE/`, `.github/DISCUSSION_TEMPLATE/`.
3. Create files A–I.
4. Run `make validate-static` to ensure markdownlint + js-yaml pass.
5. Stage and commit: `feat(github): add issue, discussion and PR templates`.
6. Report to user: files created + user setup checklist (Discussions categories, labels, CODEOWNERS handle confirmed).

## User setup checklist (report in Spanish)

1. Enable **Discussions** in repo Settings → create categories: `Announcements`, `Ideas`, `Q&A`, `General` (lowercase slugs).
2. Create labels: `bug`, `feature`, `phase`, `area/component`, `area/ci`, `area/docs`, `area/security`, `area/process`.
3. Confirm CODEOWNERS handle: @Santiago1010 (already confirmed).
4. All of the above happen in GitHub UI right BEFORE the first push.

## Verification

- `make validate-static` passes (markdownlint + js-yaml + yamllint + bash -n).
- All YAML forms are valid js-yaml.
- All markdown is markdownlint-clean.
- No phase numbers or gates invented; every reference matches `docs/roadmap.md` / `docs/architecture.md`.
- Single conventional commit; working tree clean; nothing pushed.
