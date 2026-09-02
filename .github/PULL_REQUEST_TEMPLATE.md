# Pull Request

## Summary

<!-- Explain what changes and why. -->

## Changes

<!-- List the relevant files, components and environment impact. -->

## Validation

<!-- Include commands and results. -->

## Checklist

- [ ] I have read [CONTRIBUTING.md](CONTRIBUTING.md).
- [ ] Content is in English.
- [ ] No secrets, kubeconfigs or generated artifacts are committed.
- [ ] Docs updated in this PR: roadmap Work Log row (`docs/status.md` roadmap)
      *and* the component's Status column in `docs/architecture.md`.
- [ ] All four `envs/<env>/<component>.yaml` overlays updated (or intentionally
      local-only and documented in `docs/architecture.md`).
- [ ] Sync-waves respected: operators/CRDs before CRs, Vault before ESO
      consumers, datastores before consumers; new component wave is ≥10 apart
      from its dependencies.
- [ ] Functional DoD gate verified (per the per-component Definition of Done in
      `docs/status.md`): app Synced + Healthy, no CrashLoop/ImagePullBackOff,
      ExternalSecret `SecretSynced` where applicable, one functional smoke.
- [ ] `make validate-static` passes.
- [ ] Live validation was run, or the limitation is documented.
