# Security Posture

The security controls wired into the repository and its CI. This is a
**state document**: controls shipped in Phase 0.0 exist and run in CI; anything
marked *planned* (checkov baseline enforcement, cluster smoke) is not active
yet. For secret handling see [secrets.md](secrets.md); for the CI workflow map
see [ci-cd.md](ci-cd.md).

## CI security controls

| Control | Workflow | Behavior today |
| --- | --- | --- |
| gitleaks | security.yml | Secrets/password scan on push and PR; blocks on findings |
| checkov (static IaC) | security.yml | IaC misconfiguration scan of YAML manifests |
| checkov baseline | — | Exists in the repo but is **re-examined** before enforcement; reason: the previous attempt's baseline hid real findings while its cluster smoke was broken |
| CodeQL | codeql.yml | Static analysis on push + PR + weekly schedule |
| OpenSSF Scorecard | scorecard.yml | Attestation on push + weekly; feeds the README badge |
| Pin guards | security.yml | Fails any chart reference or image tag that is `latest` or floating |

Deploy-time security (no pages by design in the radar, manual prod sync) is
covered in [observability-radar.md](observability-radar.md) and
[workflow.md](workflow.md).

## Repository rules that enforce the posture

- **Pinning enforcement**: images and charts are official upstream releases
  pinned by version — never `latest`, never floating tags (repo rule, CI
  guard, and ADR). The previous attempt drifted because this was not enforced.
- **Secrets never in git**: `.env`, `.secrets/`, kubeconfigs, unseal keys and
  tokens are gitignored; Vault is the SSOT (see [secrets.md](secrets.md)).
- **No commit-time credentials**: Vault design is described in the docs but
  never filled; placeholders are `{{GIT_REPO_URL}}`-style and substituted at
  bootstrap.
- **Sign-offs**: prod sync is manual with a human go/no-go in the deploy
  window; nothing is deployed by hand after bootstrap.

## Baseline re-examination (planned)

Before the checkov baseline becomes a merge gate, it is re-derived from a
**green** platform (post Phase 18 smoke) and its entries are annotated with
owners. Until then, checkov runs online but the baseline is advisory: real
findings surface as PR comments, not silent baseline entries.

## Settings checklist (out of repo)

When publishing the repository to GitHub, enable inline: secret scanning and
push protection; branch protection on `main` (require CI + review);
CODEOWNERS for `argocd/` (optional, if the org wants it). This list lives here
because it is configuration of the hosting side, not of this repository.

## Runbook: leaked secret

1. gitleaks (CI) blocks; rotate the secret **before** deleting it.
2. If it reached history: rewrite/delete it, then rotate again (it is
   compromised).
3. Record the incident in the [deviations log](architecture.md#deviations-log)
   so the admission control improves.
4. Never `git push --force` past a secure baseline without the rotation.
