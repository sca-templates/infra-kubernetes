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

**Tipo *y* paths deciden el release.** Both the commit type and the paths it
touches gate whether a release opens. The root package in
`.release-please-config.json` carries
`exclude-paths: [".github", "0.Project_info", "bootstrap"]`
(exact directory names): a commit is dropped **only if every file it changes
stays inside those directories** — CI tweaks, the smoke harness, docs and
agent notes never open a release PR on their own; a commit that *also* touches
the deployed surface (`infrastructure/`, `envs/`, `argocd/`, `charts/`) still
releases. Root-level files (`Makefile`, `README.md`, …) are not under any
directory and always count, so keep `feat`/`fix` off commits that only touch
them (the path match works per directory, not per file).

## How a release happens

1. A `feat`/`fix`/breaking commit is merged to `main`.
2. The `Release` workflow runs; release-please opens a **release PR** that
   adds `CHANGELOG.md` (new version section), bumps
   `.release-please-manifest.json`, and targets `main`.
3. The release PR goes through the **same gates as any other PR**: `Validate`
   and `Security` run on it (a dedicated token minted from the
   `sca-bot-release` GitHub App, not the default `GITHUB_TOKEN`, is used
   precisely so those checks run — resources opened with `GITHUB_TOKEN` do not
   trigger workflow runs), and it needs human review + merge.
4. On merge, the workflow tags the merge commit (`vX.Y.Z`) and creates the
   GitHub Release **as a draft** (`draft: true` in
   `.release-please-config.json`). The tag is re-created by the **`sign-tag`
   job** (inside the shared `shared-release-flow.yml` template) as an annotated
   tag signed by the dedicated release bot key, then force-pushed to the same
   commit (see Deviations). The job checks out the tag's commit first, so the
   GPG import happens inside a git work tree.
5. The **`hold` job** (local, in [release.yml](../.github/workflows/release.yml))
   then publishes the release and explicitly declines `latest` in a single
   PATCH. The next section explains why the draft cannot be left to stand and
   why this step exists.

A merge opens no release PR when its type is `docs`/`chore`/`ci`/`test`, or
when every file of its `feat`/`fix` falls under an `exclude-paths` directory.

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

## Publishing a release (promotion to `latest`)

**The tag is the artifact; the release entry is the announcement; the `latest`
designation is a third, separate decision.** Merging the release PR produces the
tag and a public release that is *not* `latest`. `latest` moves only when a human
runs the **`Release promote`** workflow
([release-publish.yml](../.github/workflows/release-publish.yml)) with the tag as
input, after the release has been validated and adopted.

### Why a bot is needed at all

release-please cannot express "publish without claiming `latest`". It calls
`repos.createRelease` with only `draft`, `prerelease` and `target_commitish`, and
GitHub's `make_latest` parameter **defaults to `true` for newly published
releases** — "Drafts and prereleases cannot be set as latest" (REST API, *Create
a release* / *Update a release*). So the only levers release-please has are
`draft` and `prerelease`, and any full release it publishes takes the pointer on
its own. `gh release edit --latest` is the only way to move or withhold it, and
that is a bot step — the same reason the service flow ends in `mark-latest`
([workflow.md](workflow.md)).

| State | Public | Notifies | Can be `latest` | Who sets it |
| --- | --- | --- | --- | --- |
| draft | no (write access only) | no | no | release-please (`draft: true`) |
| pre-release | yes, badged | yes | no | release-please (`prerelease: true`) |
| full, not `latest` | yes, unbadged | yes | no | the `hold` job (`make_latest=false`) |
| full, `latest` | yes | yes | yes | `Release promote` (human) |

`draft` is the **transient**, not the end state: it is the only creation-time
lever that keeps a release off `latest` *atomically*. Publishing it into a plain
full release instead would mean a window in which GitHub has already claimed
`latest` and the bot has to walk it back.

### Why the `hold` job exists

`draft` alone does not survive the run. The shared `sign-tag` job replaces the
API-created lightweight tag with the signed annotated one via
`git push -f refs/tags/<TAG>`, and **that tag rewrite publishes the draft**.
Measured on this repository: the release's `created_at` lands inside the
`sign-tag` job window on every release since `v0.7.0`, while `published_at`
lands inside the `Release please` window.

Left alone, that made every release public and `latest` by itself, and left
`Release promote` unreachable — its `isDraft` guard could never pass, which is
why it had zero runs. `hold` runs *after* the shared flow and is the
authoritative transition: `gh release edit --draft=false --latest=false` in one
PATCH, so the release never spends a moment published *and* `latest`. Being last
in the run makes it independent of whatever the tag force-push did to the flags.
`v0.10.0` had to be unmarked by hand for exactly this reason.

`hold` is local rather than a fix in `CI-CD-Templates` so it can be proven on a
release before the org-wide semantics change. The bug is upstream and still
present on the template's `main`; the upstream fix is the same command inside
`sign-tag`, where the tag is already in `needs.release.outputs.tag_name`.

### The promotion gate

Promotion is guarded, in order: the tag exists, it is **annotated**, its
signature verifies against the committed trust anchor
([`.github/release-bot-gpg.pub`](../.github/release-bot-gpg.pub)), the release
is published, and it is not a pre-release. A tag that the `sign-tag` job did not
sign cannot be promoted, so the `latest` pointer can never drift onto a
hand-made or unsigned ref. Re-dispatching an already-promoted tag is a no-op, so
a half-failed promotion can simply be re-run.

```bash
gh workflow run release-publish.yml -f tag=v0.10.0
```

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
| Signing job | `shared-release-flow.yml` (CI-CD-Templates) → `crazy-max/ghaction-import-gpg` (pinned) |

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

### Re-signing an existing tag (removed)

The `Release` workflow used to accept a manual `workflow_dispatch` with
`tag_name` + `commit_sha` to (re)sign an existing tag **without** creating a
new release. That path was a one-off for `v0.1.0` (the tag was released before
the signing job existed) and is **no longer offered**: since the migration to
the shared `shared-release-flow.yml` template, `release.yml` responds only to a
push to `main`, and tag signing runs only when a release was created. The
`v0.1.0` tag was promoted once from the API-created lightweight ref to the
signed annotated tag, pinned to commit `0e39a99`, before the migration; if an
existing tag ever needs (re)signing again, re-sign it with `git tag -sf` and a
force-push, or add a manual path to the shared template first.

The `Release promote` dispatch is a different thing and is **not** a re-sign
path: it moves the `latest` pointer and never touches the tag.

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
| Release publication | The release is published **off** `latest` by the `hold` job (`make_latest=false`); only the manual `Release promote` workflow claims `latest` | `latest` is a human go/no-go tied to adoption, the same rule service releases follow. release-please cannot express "publish without claiming `latest`" (`make_latest` defaults to `true`), and the shared flow's tag force-push publishes the draft, so the hold is re-asserted after it. See [Publishing a release](#publishing-a-release-promotion-to-latest) |
| Release automation token | A per-run installation token minted from the `sca-bot-release` GitHub App (`APP_ID` + `APP_PRIVATE_KEY`, scoped to `infra-kubernetes`) instead of the default `GITHUB_TOKEN` | `GITHUB_TOKEN`-created resources do not trigger workflow runs, so the release PR would never run the required checks and could not merge |

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
