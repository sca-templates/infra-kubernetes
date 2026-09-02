# Contributing to infra-kubernetes

> GitOps source of truth for the `sca` Kubernetes platform. Changes are
> reviewed and reconciled through ArgoCD.

## Ground Rules

- **English only** for repository content, commits and pull requests.
- **No secrets in the repository**. Keep `.env`, `.secrets/`, kubeconfigs,
  tokens and certificates out of git.
- **No manual deployment**. After bootstrap, commit and push changes for
  ArgoCD to reconcile.
- Use conventional commits such as `feat(platform): add component values`.

## Roadmap is Source of Truth

Read `docs/roadmap.md` before any change. Every delivery change is a **phase**:
one component, one commit, one PR, one review. The roadmap defines the
dependency graph, the sync-wave order, and the per-component Definition of Done
gate. Phases 0.x scaffold the repository and are not delivery projects.

The shared DoD for every phase:

- Application `Synced` + `Healthy` in ArgoCD.
- Pods `Running`, no `CrashLoopBackOff` / `ImagePullBackOff` after 2+ min stable.
- `ExternalSecret` -> `SecretSynced` where applicable.
- One functional smoke (per-project gate).
- `make status` shows no new `Degraded`.
- Docs updated in the same commit (Work Log + `architecture.md` + `status.md`).

## Preview-over-Branch Technique

For components that need live validation before merge:

1. Create a feature branch and push it.
2. Point ArgoCD's `targetRevision` at the feature branch for preview.
3. Once the DoD gate passes, revert `targetRevision` to `main`.
4. Merge the PR — ArgoCD reconciles the final state from `main`.

This keeps the preview branch ephemeral and the main branch as the single
source of truth.

## Rollback, Not Fix Chains

If a component does not turn green after merge: **roll it back**. Do not
chain `fix` commits, do not apply ad-hoc `ignoreDifferences` or SSA patches,
and never deploy by hand after `make bootstrap`. A blocked component rolls
back; the next attempt starts fresh.

## Making Changes

1. Read `AGENTS.md` and the relevant documents in `docs/` (start at
   `docs/INDEX.md`) before changing topology, ports, networks or component
   behavior. Consult the `sca-docs` notes referenced there for ecosystem
   conventions.
2. For shared base values, update all four environment overlays:
   `local`, `dev`, `qa` and `prod`.
3. Preserve the documented sync-wave dependency order
   (`docs/architecture.md`).
4. Run `make validate-static` before opening a pull request; with the local
   hooks installed you can also run `pre-commit run --all-files` for faster
   feedback (yamllint, actionlint, gitleaks).
5. CI enforces secrets (`Security -> gitleaks`), IaC posture
   (`Security -> checkov`, baseline in `.checkov.baseline`) and the image/version
   pinning policy (`Security -> guards`). Keep these in mind before pushing.
6. Include validation results and any live-cluster limitations in the pull
   request description.

## Adding a Component

Follow the checklist in `docs/onboarding-new-service.md` and in
`.claude/skills/platform-lifecycle/SKILL.md`: component directory, base
values, four environment overlays, ApplicationSet entries, sync-wave
assignment, secrets and validation. Use the **Phase / component addition**
issue template to track the work.

## Environment Gradient

- **local**: lightest profile, 1 replica, minimal resources, auto-sync + prune.
- **dev**: reduced HA, auto-sync + prune.
- **qa**: HA (3 replicas, PDBs, anti-affinity), auto-sync, **no prune** — mirrors
  prod with minimum resources.
- **prod**: full HA, real storage, **manual sync**.

Promotion follows the `promote-test` gate in `docs/workflow.md`.

## Questions and Issues

- **Questions**: use [Discussions (Q&A)](https://github.com/sca-templates/infra-kubernetes/discussions/categories/q-a).
- **Bugs**: use the [Bug report](https://github.com/sca-templates/infra-kubernetes/issues/new?template=bug_report.yml) issue template.
- **Features**: use the [Feature request](https://github.com/sca-templates/infra-kubernetes/issues/new?template=feature_request.yml) issue template.
- **Phase tasks**: use the [Phase / component addition](https://github.com/sca-templates/infra-kubernetes/issues/new?template=phase_task.yml) issue template.
- **Security**: see [SECURITY.md](../SECURITY.md). Do not open public issues for vulnerabilities.

## Definition of Done

- [ ] Content is in English.
- [ ] No secrets, kubeconfigs or generated artifacts are committed.
- [ ] All required environment overlays are updated.
- [ ] Sync-wave ordering is documented and respected.
- [ ] `make validate-static` passes.
- [ ] No new secrets, floating image tags or un-baselined checkov findings
      (`Security` workflow is green).
- [ ] `README.md` and the relevant `docs/` files are updated when behavior
      or topology changes.

## License

This repository is licensed under the MIT License. See [LICENSE](../LICENSE).
