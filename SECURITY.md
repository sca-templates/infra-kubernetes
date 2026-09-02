# Security Policy

This repository is the GitOps source of truth for the `sca` platform on
Kubernetes: every change ArgoCD applies travels through this git history.
That makes integrity of this repository the highest security value.

## Supported versions

The platform is maintained as a single track. The only supported revision is
the tip of `main`, reconciled continuously by ArgoCD in the `local`, `dev`,
`qa` and `prod` environments. There are no LTS branches.

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
  static validation + human review — see [docs/ci-cd.md](docs/ci-cd.md).)
- If the report involves a leaked credential (Vault token, unseal key, S3
  key, …) the secret is considered **compromised**: rotated at the source and
  in Vault, never just removed from git. Containment steps are documented in
  [docs/security.md](docs/security.md).

## Automated posture

The repository enforces, from `main`, the checks described in
[docs/security.md](docs/security.md): gitleaks secret scanning, checkov
infrastructure posture (baseline re-examined before enforcement), image/version
pinning guards, CodeQL on the GitHub Actions files and an OpenSSF Scorecard.
Secrets must never be committed — the CI blocks pushes that leak them.

## Scope

This policy covers the infrastructure-as-code in this repository. The
services it deploys (Kong, Keycloak, Kafka, Redis, PostgreSQL, …) follow the
security policy of their own upstream projects and of the
[sca-docs](https://github.com/sca-templates/sca-docs) ecosystem notes.