# Versioning, Releases and the CHANGELOG

How `infra-kubernetes` versions itself. Releases, tags and the `CHANGELOG.md`
are **automated** by [release-please](../.github/workflows/release.yml) on
[conventional commits](https://www.conventionalcommits.org/) — this repository
has no `package.json` and builds nothing, so the automation is configured for a
plain repository (see `.release-please-config.json`).

## Versioning scheme

Pre-1.0 semantic versioning, starting at `v0.1.0`. The manifest
(`.release-please-manifest.json`) seeds the current version; release-please
computes the next one from the commits merged since the last release tag:

| Commit type on `main` | Version bump |
| --- | --- |
| `feat(...)` (a component/phase landing) | minor |
| `fix(...)` | patch |
| `feat(...)!:` / `BREAKING CHANGE:` | minor (pre-1.0 its equivalent of a major) |
| `chore`, `docs`, `ci`, `test`, refactors | no release — merges without a version bump |

Because every phase lands as one `feat(platform): …` commit, **each released
component produces one release**. The first release (`v0.1.0`) covers the whole
pre-release history; subsequent components are additive minors.

## How a release happens

1. A `feat`/`fix`/breaking commit is merged to `main`.
2. The `Release` workflow runs; release-please opens a **release PR** that
   adds `CHANGELOG.md` (new version section), bumps
   `.release-please-manifest.json` and `version.txt`, and targets `main`.
3. The release PR goes through the **same gates as any other PR**: `Validate`
   and `Security` run on it (a dedicated `RELEASE_PLEASE_TOKEN` PAT, not the
   default `GITHUB_TOKEN`, is used precisely so those checks run — resources
   opened with `GITHUB_TOKEN` do not trigger workflow runs), and it needs
   human review + merge.
4. On merge, the workflow tags the merge commit (`vX.Y.Z`) and creates the
   GitHub Release. The tag is re-created by the **`sign-tag` job** as an
   annotated tag signed by the dedicated release bot key, then force-pushed
   to the same commit (see Deviations). The job first runs a fresh
   `actions/checkout` at the tag's commit, so the GPG import happens inside a
   git work tree (`f8d50f4`; the earlier version failed because it imported
   the key before checking anything out).

`docs` / `chore` / `ci` merges never open a release PR.

### Ad-hoc versions

A commit body containing `Release-As: x.y.z` makes release-please open a
release PR for exactly that version (e.g. a coordinated platform cut). Use it
rarely and with a review gate — the normal flow is automatic. The initial
`0.1.0` is bootstrapped this way, so the first cut is deterministic regardless
of pre-release history.

> **Squash-merge gotcha (first release almost became `1.0.0`):** the repo
> merges PRs with **squash**, and GitHub concatenates the squashed message as
> `subject` + a `* <commit message>` bullet per commit. `Release-As` is only
> parsed as a conventional-commit **footer**, i.e. it must sit in the **final
> paragraph** of the merged message. The automation commit that introduced
> release-please carried `Release-As: 0.1.0`, but the squash buried it mid-body
> and release-please silently computed `1.0.0`; it was corrected by landing a
> `chore(release)` commit whose body ends, verbatim, with `Release-As: 0.1.0`.
> **Rule: when forcing a version, put the footer as the last line of the last
> commit of the PR**, and confirm with `release-pr --dry-run` before merging.

## Signed release tags

Every release tag is signed by a **dedicated, single-purpose GPG key** for the
release bot. The release of record is **`v0.1.0`** (first release,
2026-09-05): an annotated tag at commit `0e39a99` (merge of PR #33), signed by
the release bot — `git tag -v v0.1.0` shows
`Good signature from "SCA Release Bot"`.

| Item | Value |
| --- | --- |
| Purpose | Releases only — never used for anything but signing release tags |
| Key ID / fingerprint | `E272B06540C49A7EF2AA22A22D7114035EB46A21` |
| Public key | [`.github/release-bot-gpg.pub`](../.github/release-bot-gpg.pub) (committed trust anchor) |
| Private key | CI secret `RELEASE_GPG_PRIVATE_KEY` (repo secrets), never in git; lockbox backup per [GOVERNANCE](../.github/GOVERNANCE.md) |
| Signing job | `.github/workflows/release.yml` → `crazy-max/ghaction-import-gpg` (pinned) |

Verify a tag after pulling:

```bash
git fetch --tags origin
gpg --import .github/release-bot-gpg.pub    # once — committed trust anchor
git tag -v v0.1.0
```

The output shows a `Good signature from "SCA Release Bot"` line with the
fingerprint above. Rotation is a **repository-level** action: generate a new
key, replace the `RELEASE_GPG_PRIVATE_KEY` secret, update this table and
`.github/release-bot-gpg.pub`, then re-sign future tags. History itself is not
rewritten when a key rotates.

### Re-signing an existing tag

The `Release` workflow also accepts a manual `workflow_dispatch` with two
optional inputs, `tag_name` + `commit_sha`, to (re)sign an existing tag
**without** creating a new release: the `sign-tag` job runs whenever
`releases_created == 'true'` *or* the workflow is dispatched manually. The
initial `v0.1.0` tag was released before the signing job existed; it was
promoted from the API-created lightweight ref to the signed annotated tag with
exactly this dispatch, pinned to commit `0e39a99`.

## CHANGELOG.md

Generated by release-please, never hand-edited. Merge conflicts on the
`CHANGELOG.md` header lines between release PRs are resolved by taking the
release-please content — the previous attempt drifted precisely because this
file was curated by hand. The release PR must still pass the same static gates
(markdownlint runs over `**/*.md`, including the level of the changelog).

## Deviations

| Item | Deviation | Reason |
| --- | --- | --- |
| Tag lifecycle | The API-created lightweight tag is replaced by an annotated, signed tag at the same commit (force-push by the release bot) | GitHub Releases are created from the API, which only produces lightweight refs; re-signing keeps the release, its notes and the signature on one object |
| Release automation token | A dedicated PAT (`RELEASE_PLEASE_TOKEN`) instead of the default `GITHUB_TOKEN` | `GITHUB_TOKEN`-created resources do not trigger workflow runs, so the release PR would never run the required checks and could not merge |

## Local parity

The release flow runs on `main` only; there is no local counterpart. To
inspect what a release PR would look like before it merges:

```bash
npx release-please release-pr \
  --repo-url=sca-templates/infra-kubernetes \
  --target-branch=main \
  --config-file=.release-please-config.json \
  --manifest-file=.release-please-manifest.json \
  --dry-run
```
