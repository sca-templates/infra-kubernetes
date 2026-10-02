# Security Posture

The security controls wired into the repository and its CI. This is a
**state document**: controls shipped in Phase 0.0 exist and run in CI; reality
is reported as it is. From Phase 1 the checkov **baseline** gates new IaC
findings and the cluster smoke is a required PR check (`Smoke` on `main`,
branch protection) — see
[ci-cd.md](ci-cd.md)). For secret handling see [secrets.md](secrets.md); for
the CI workflow map see [ci-cd.md](ci-cd.md).

## CI security controls

| Control | Workflow | Behavior today |
| --- | --- | --- |
| gitleaks | security.yml (via shared template) | Secrets/password scan on push and PR; blocks on findings |
| checkov (static IaC) | security.yml (local job) | IaC misconfiguration scan of YAML manifests |
| osv-scanner (SCA) | security.yml (via shared template) | Open-source dependency vulnerability scan on push + PR; honours `.github/osv-scanner.toml` ignores |
| checkov baseline | security.yml (local job) | `.github/checkov-baseline.json` gates **new** findings since Phase 1 — the pod on `bootstrap/local-git-server.yaml` is documented (local-only tooling); anything else fails the PR as it would without the baseline |
| CodeQL | codeql.yml (shared template) | Static analysis on push + PR + weekly schedule |
| Pin guards | security.yml (local job) | Fails any chart reference or image tag that is `latest` or floating |
| Release tag signing | release.yml (shared template) | Every release tag is re-signed with the dedicated **release-bot** GPG key (private key in repo secret `RELEASE_GPG_PRIVATE_KEY`) |

`security.yml` runs gitleaks + osv-scanner through the org shared
`shared-security-scan.yml` (SHA-pinned to the v3.0.0 release; gitleaks + osv
only) and keeps checkov + pin guards as local jobs. The
wrapper workflows delegate to
[sca-templates/CI-CD-Templates](https://github.com/sca-templates/CI-CD-Templates)
— see [ci-cd.md](ci-cd.md) for the map. A gitleaks finding still fails the PR;
the shared template uploads the SARIF only on non-PR events, so PR runs block
on findings but skip the code-scanning alert (same-repo PRs included).

Deploy-time security (no pages by design in the radar, manual prod sync) is
covered in [observability-radar.md](observability-radar.md) and
[workflow.md](workflow.md). Service dev/qa deploys run outside this repo: the
service's `promote` workflow talks to the ArgoCD API with a **scoped token**
(`ARGOCD_SERVER` / `ARGOCD_TOKEN`, RBAC restricted to `sync`/`get` on the
service's own `<service>-dev` and `<service>-qa` applications) — no kubeconfig
or cluster credential is ever stored in CI, and no pipeline can touch other
services or prod.

## Release signing

Release tags are signed by a dedicated, single-purpose release-bot key —
fingerprint `E272B06540C49A7EF2AA22A22D7114035EB46A21`, public trust anchor in
`.github/release-bot-gpg.pub`. The private key lives only in the
`RELEASE_GPG_PRIVATE_KEY` repo secret and a lockbox backup; it is imported (by
SHA-pinned `crazy-max/ghaction-import-gpg`) only inside the `sign-tag` job of
the shared `shared-release-flow.yml` (invoked by `release.yml`). Verification
and rotation policy in
[versioning.md](versioning.md).

## Python dependency pinning

All CI Python dependencies are hash-pinned. Each install uses
`pip install --require-hashes -r <lockfile>` so every transitive dependency is
verified against a SHA-256 digest (checkov is the one install that also needs
`--no-deps`, for the reason in the override section below):

| Tool | Lockfile | Source |
| --- | --- | --- |
| checkov (IaC) | `.github/requirements.txt` | compiled with `uv pip compile --generate-hashes` |
| yamllint | `.github/requirements-yamllint.txt` | compiled with `uv pip compile --generate-hashes` |

Lockfiles are generated, not hand-edited. To regenerate after a tool bump:

```bash
printf 'checkov==<version>\n' | uv pip compile --generate-hashes --python-version 3.11 -o .github/requirements.txt -
printf 'yamllint==<version>\n' | uv pip compile --generate-hashes --python-version 3.11 -o .github/requirements-yamllint.txt -
```

Always pass `--exclude-newer <ISO-8601 cutoff>`: a lockfile is a snapshot of one
day, and without a cutoff uv also lifts every unrelated package in the closure
to its newest release, burying the intended bump in a thousand-line diff.

### The asteval override (checkov)

`checkov==3.3.16` hard-pins `asteval==1.0.6` in every 3.3.x release (3.3.16
through 3.3.19, the latest), and the two advisories that reach us through that
pin are fixed in `asteval>=1.0.9`. The closure is therefore unsatisfiable as
resolved, and the default outcome is an accepted-risk ignore. This repo forces
the fixed version instead, so the lockfile carries the fix rather than the
manifest carrying a waiver:

- `.github/asteval-override.txt` — the constraint, with the reasoning inline;
- `.github/requirements.txt` — compiled against it, so `asteval==1.0.10` is
  hash-pinned and reviewed like every other entry;
- `.github/workflows/security.yml` — installs the set with
  `--no-deps --require-hashes`.

```bash
printf 'checkov==3.3.16\n' | uv pip compile --generate-hashes --python-version 3.11 \
  --exclude-newer 2026-09-16T00:00:00Z \
  --overrides .github/asteval-override.txt -o .github/requirements.txt -
```

The cutoff is also what makes a fix installable, and `--upgrade-package` is
required either way: `uv pip compile` treats the versions already in the output
file as *preferences*, so a re-compile never revisits them. Without the flag the
lockfile recompiles unchanged and the advisory stays — nothing constrains the
package, it is simply never re-resolved. What differs is whether the cutoff
moves:

- **The fixed version predates the current cutoff** — the cutoff already admits
  it, so only the package is named. `gitpython` is the case in point:
  `3.1.62` shipped 2026-09-07, inside the `2026-09-16` cutoff, but `3.1.61` had
  been pinned before it and survived as a preference. Three-line diff, header
  untouched.
- **The fixed version postdates the current cutoff** — the cutoff has to move to
  the day of the fix release, or the version does not exist as far as the
  resolver is concerned. `urllib3==2.8.0` shipped 2026-09-15, after the
  `2026-09-02` cutoff, so that bump moved it to `2026-09-16T00:00:00Z`: a
  six-line diff, the header plus the entry.

```bash
printf 'checkov==3.3.16\n' | uv pip compile --generate-hashes --python-version 3.11 \
  --exclude-newer 2026-09-16T00:00:00Z \
  --overrides .github/asteval-override.txt \
  --upgrade-package <pkg> -o .github/requirements.txt -
```

Read the release date of the fixed version against the cutoff in the header
before recompiling: it decides the `--exclude-newer` value. Both mistakes are
cheap to make and only the missing `--upgrade-package` fails silently, as a
lockfile that diffs to nothing.

`--no-deps` is a requirement of the override, not a shortcut. pip re-checks the
install against the *declared metadata* of every distribution, and checkov's own
`asteval==1.0.6` pin conflicts with the overridden version, so a resolving
install fails with `ResolutionImpossible`. Skipping re-resolution makes the
reviewed lockfile the truth: every distribution is hash-verified, the closure
was hand-picked and diffed in review, and only checkov's declared metadata goes
unchecked at install time — a build-time tool that scans manifests, not a
runtime component. Regenerate with `uv`, never `pip-compile`, so the override
applies and the closure stays minimal.

There is deliberately **no `pip` Dependabot watch** on `/.github`. Dependabot's
pip updater cannot read a uv override or honour `--exclude-newer`: it treats
`.github/asteval-override.txt` as a requirements file (the `==` is a valid
pin) and rewrites the version this repository forces into the toolchain, then
re-resolves the whole closure to "latest". That lands versions which violate
checkov's own declared constraints — `networkx<2.7`, `packaging<24.0`,
`cachetools<6.0.0`, `cyclonedx-python-lib<8.0.0`, `aiodns<4.0.0`,
`boto3==1.35.49` — so the lockfile stops describing an installable set and the
IaC gate fails. Bumps are applied by hand with the commands above and reviewed
as the ~6-line diff they are. Retire the override when checkov adopts
`asteval>=1.0.9`: drop the file, drop `--no-deps`, and delete the two
`IgnoredVulns` entries.

### Ignored OSV advisories (via osv-scanner.toml)

The shared security scan flags one OSV advisory in the checkov dependency
chain. It is **inherent to checkov and has no fix in its resolution**, so it is
explicitly ignored through `.github/osv-scanner.toml` (the standard ignore
mechanism, honoured by `osv-scanner`) placed next to the
`.github/requirements.txt` manifest that carries it:

| OSV | Package | Advisory | Mechanism |
| --- | --- | --- | --- |
| PYSEC-2026-1325 | ecdsa | Minerva P-256 timing attack | ignored — no upstream fix (out of scope) |

Rationale: `checkov==3.3.16` (current) declares `ecdsa<1.0.0,>=0.19.0`, which
resolves to `ecdsa==0.19.2` (latest), and that release still carries the
Minerva advisory — upstream explicitly considers side-channel attacks out of
scope and publishes no fix. `ecdsa` is a build-time CI dependency, not a
runtime component of the platform, and its vulnerable surface is not reachable
from `checkov`'s IaC-scanning usage. It is re-evaluated when upstream publishes
a fix.

The two `asteval` advisories (GHSA-89v8-rhwq-hf77, GHSA-9w56-46f6-3qhx) are
**no longer ignored**. `checkov==3.3.16` hard-pins `asteval==1.0.6`, from which
they are reachable, but the lockfile override above forces `asteval==1.0.10`
past that pin, so the vulnerable version is not in the closure at all. Accepted
risk was the fallback while no fix was installable; the fix is installable, so
the entries are gone rather than re-justified.

## Repository rules that enforce the posture

- **Pinning enforcement**: images and charts are official upstream releases
  pinned by version — never `latest`, never floating tags (repo rule, CI
  guard, and ADR). The previous attempt drifted because this was not enforced.
- **Secrets never in git**: `.env`, `.secrets/`, kubeconfigs, unseal keys and
  tokens are gitignored; Vault is the SSOT (see [secrets.md](secrets.md)).
  The CI release secrets (`APP_ID`, `APP_PRIVATE_KEY`,
  `RELEASE_GPG_PRIVATE_KEY`) live only as encrypted GitHub Actions secrets,
  never in the repository (storage model in [secrets.md](secrets.md)).
- **No commit-time credentials**: Vault design is described in the docs but
  never filled; placeholders are `{{GIT_REPO_URL}}`-style and substituted at
  bootstrap.
- **Sign-offs**: prod sync is manual with a human go/no-go in the deploy
  window; nothing is deployed by hand after bootstrap.

## Baseline re-evaluation (Phase 18)

The checkov baseline (`.github/checkov-baseline.json`) gates new findings from
Phase 1: entries are documented, intentional manifests whose findings are
accepted and recorded. The baseline is **re-evaluated** post Phase 18 from a
green platform and its entries annotated with owners. Until then the only way a
new entry appears is a reviewed PR that regenerates the baseline — new findings
never pass silently.

## Settings checklist (out of repo)

When publishing the repository to GitHub, enable inline: secret scanning and
push protection; branch protection on `main` (require review + status checks
including `Smoke` for `pr-cluster.yml`); CODEOWNERS for `argocd/` (optional,
if the org wants it). This list lives here because it is configuration of the
hosting side, not of this repository.

## Runbook: leaked secret

1. gitleaks (CI) blocks; rotate the secret **before** deleting it.
2. If it reached history: rewrite/delete it, then rotate again (it is
   compromised).
3. Record the incident in the [deviations log](architecture.md#deviations-log)
   so the admission control improves.
4. Never `git push --force` past a secure baseline without the rotation.
