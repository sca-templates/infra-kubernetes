# Security Policy

This repository is the GitOps source of truth for the `sca` platform on
Kubernetes: every change ArgoCD applies travels through this git history.
That makes integrity of this repository the highest security value.

## Supported versions

The platform is maintained as a single track. The only supported revision is
the tip of `main`, reconciled continuously by ArgoCD in the `local`, `dev`,
`qa` and `prod` environments. There are no LTS branches. Release tags are
signed annotated snapshots of `main` (currently `v0.1.0`, see
[docs/versioning.md](../docs/versioning.md)) — integrity evidence, not support
branches.

## Reporting a vulnerability

Do **not** open a public issue for anything security related. Report it
privately:

1. Go to **Security → Report a vulnerability** in this repository (GitHub
   private advisory).
2. Give the advisory a severity and, if known, the affected file(s) and a
   minimal description of the impact.
3. Keep the advisory private until a fix is deployed across every environment.

For all `sca` repositories, use the same private-advisory channel on the
repository where the flaw lives; the maintainers triage across the ecosystem.

## What we do once a report lands

- Reproduce and assess severity, then fix through a normal PR that must pass
  `Validate`, `Security` and the smoke checks before merging to `main`. (The
  cluster-smoke workflow returns in later phases; until then the merge gate is
  static validation + human review — see [docs/ci-cd.md](../docs/ci-cd.md).)
- If the report involves a leaked credential (Vault token, unseal key, S3
  key, …) the secret is considered **compromised**: rotated at the source and
  in Vault, never just removed from git. Containment steps are documented in
  [docs/security.md](../docs/security.md).

## Automated posture

The repository enforces, from `main`, the checks described in
[docs/security.md](../docs/security.md): gitleaks secret scanning, checkov
infrastructure posture (baseline re-examined before enforcement), image/version
pinning guards, CodeQL on the GitHub Actions files, an OpenSSF Scorecard and
release-tag signing by a dedicated bot key. Secrets must never be committed —
the CI blocks pushes that leak them.

## Scope

This policy covers the infrastructure-as-code in this repository. The
services it deploys (Kong, Keycloak, Kafka, Redis, PostgreSQL, …) follow the
security policy of their own upstream projects and of the
[sca-docs](https://github.com/sca-templates/sca-docs) ecosystem notes.

## Security assurance case

### Threat model

| Threat | Trust boundary | Risk | Countermeasure |
| --- | --- | --- | --- |
| Leaked secrets (tokens, keys, kubeconfigs) | Git history | Unauthorized access to platform | gitleaks on every push; `.secrets/` gitignored; Vault as SSOT |
| Floating or compromised image tags | CI gate | Supply-chain attack via malicious image | Pin guards reject `latest`/floating tags; `security.yml` blocks merges |
| Vulnerable dependencies | CI pipeline | Known CVE in checkov/osv-scanner/etc. | osv-scanner (SCA) on every PR; dependabot for GitHub Actions; `requirements*.txt` hash-pinned |
| Malicious Helm charts or K8s manifests | CI gate | Misconfiguration or privilege escalation | checkov (IaC posture); kube-linter (manifest lint); helm lint; kubeconform (schema) |
| Unreviewed or low-quality changes | PR review | Regression or configuration drift | Validate + Security + CodeQL + human review required; "rollback not fix chains" |
| Supply-chain compromise of CI actions | GitHub Actions | Tampered workflow or action | All actions pinned by commit SHA with version comment; lockfiles with SHA-256 hashes |
| Loss of maintainer | Personnel | Project abandoned | GOVERNANCE.md access continuity; bus-factor backup with admin access; signing keys in lockbox (release-bot private key backed up alongside) |

### Trust boundaries

1. **Git repository** (source of truth) — commits are signed; DCO attests
   contributor authorization; branch protection requires review.
2. **CI pipeline** — GitHub Actions run with `contents: read` (plus the
   `Release` workflow's `contents: write` / `pull-requests: write`, which it
   needs to open release PRs and push tags). Beyond the read-only
   `GITHUB_TOKEN`, only the `Release` workflow receives secrets — the two
   repository secrets `RELEASE_PLEASE_TOKEN` and
   `RELEASE_GPG_PRIVATE_KEY`, stored encrypted by GitHub (libsodium sealed box)
   and injected only into that workflow's jobs (see
   [docs/secrets.md](../docs/secrets.md)). CI validates and releases, but never
   deploys.
3. **ArgoCD reconciliation** — only ArgoCD may deploy; human `kubectl apply`
   is forbidden after bootstrap. Sync policies follow ADR-003.
4. **Cluster runtime** — nodes run only images from approved registries with
   pinned tags; Vault is the single source of secrets.

### Evidence of common vulnerability mitigation

- **Hardcoded secrets**: gitleaks scans every push; `.env` and `.secrets/`
  are gitignored; Vault is the SSOT for runtime secrets.
- **Known vulnerable dependencies**: osv-scanner scans on every PR; known
  unfixable advisories are documented and justified in
  `.github/osv-scanner.toml` and `docs/security.md`.
- **Floating image tags**: the `guards` job in `security.yml` blocks any
  `image: <name>:latest` or `tag: latest` on every push.
- **IaC misconfiguration**: checkov scans all YAML manifests; baseline is
  re-examined before enforcement to avoid hiding real findings.
- **Unsigned commits**: DCO sign-off is required per CONTRIBUTING.md; release
  tags are signed by the dedicated release-bot GPG key (fingerprint
  `E272B06540C49A7EF2AA22A22D7114035EB46A21`, see
  [docs/versioning.md](../docs/versioning.md)).

## Security review

A security review was performed on **2026-09-02** by the project maintainer.
It considered the security requirements and trust boundaries documented in the
[Security assurance case](#security-assurance-case) above: the git repository
and CI pipeline are the primary trust boundaries, and the mitigation evidence
there (gitleaks, osv-scanner, pin guards, checkov, kube-linter, DCO, signed
tags) is the countermeasure set weighed against the threat model.

Scope and result:

- Reviewed automated posture (secrets, dependency, IaC, pin), the assurance
  case, and the DCO/governance controls.
- No critical or high-severity open findings at review time.
- Residual gaps are tracked in [docs/status.md](../docs/status.md)
  (silver/gold badge contributors, `two_person_review`) and, for known
  unfixable dependency advisories, in `osv-scanner.toml`.

Reviews are repeated whenever the trust boundary changes materially and at
least every 5 years.
