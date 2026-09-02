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
5. CI enforces secrets (`Security → gitleaks`), IaC posture
   (`Security → checkov`, baseline in `.checkov.baseline`) and the image/version
   pinning policy (`Security → guards`). Keep these in mind before pushing.
6. Include validation results and any live-cluster limitations in the pull
   request description.

## Adding A Component

Follow the checklist in `docs/onboarding-new-service.md` and in
`.claude/skills/platform-lifecycle/SKILL.md`: component directory, base
values, four environment overlays, ApplicationSet entries, sync-wave
assignment, secrets and validation.

## Definition Of Done

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
