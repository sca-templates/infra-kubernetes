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
5. Two local jobs bracket the shared flow, in parallel with it and after it:
   **`capture`** snapshots which release was `latest` *before* this push, and
   **`finalize`** then publishes the release, holds it off `latest`, and
   re-asserts that snapshot. The next section explains why the hold needs two
   steps and not one, and what the release looks like when they are done.

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
its own. `PATCH /releases/{id}` is the only way to move the pointer, and that is
a bot step — the same reason the service flow ends in `mark-latest`
([workflow.md](workflow.md)). Withholding it is a bot step too, and it takes two
calls, not one; the next section is the measurement that says why.

| State | Public | Notifies | Can be `latest` | Who sets it |
| --- | --- | --- | --- | --- |
| draft | no (write access only) | no | no | release-please (`draft: true`) |
| pre-release | yes, badged | yes | no | release-please (`prerelease: true`) |
| full, not `latest` | yes, unbadged | yes | no | the `finalize` job |
| full, `latest` | yes | yes | yes | `Release promote` (human) |

### Why the release cannot be held off `latest` with `make_latest=false`

This is the part that took more than one attempt, so the evidence is recorded
here rather than only the conclusion.

**The `draft` does not survive the shared flow.** The `sign-tag` job replaces
the API-created lightweight tag with the signed annotated one via
`git push -f refs/tags/<TAG>`, and **that tag rewrite publishes the draft**.
Measured on this repository: the release's `created_at` lands inside the
`sign-tag` job window on every release since `v0.7.0`, while `published_at`
lands inside the `Release please` window. Publishing hands the release the
`latest` pointer, because `make_latest` **defaults to `true` for newly published
releases** (REST API, *Create a release* / *Update a release*).

**Declining it does not work either.** `make_latest=false` leaves the release
*undesignated*; it stores no pointer. `GET /releases/latest` then falls back to
"the most recent non-prerelease, non-draft release by `created_at`" (REST API,
*Get the latest release*) — and a release that was just published is by
definition that one. Measured on `v0.10.1`: the `hold` job that used to sit
here sent `--draft=false --latest=false`, exited 0, and
`GET /releases/latest` still answered `v0.10.1` (`make_latest` comes back
`null` for every release in the repository, i.e. nothing is designated at all).
The `sign-tag` force-push makes it worse by giving the new release a fresh
`created_at` (`v0.10.1`: `created_at` 17:20:28 against `published_at`
17:17:05), which pins the fallback to the newest release. `v0.10.0` had to be
un-marked by hand for exactly this reason, and `v0.10.1` is `latest` right now
for the same one.

**The only lever that stores a pointer is `make_latest=true` on an older
release.** Measured in a scratch repository through the same three states the
flow produces:

| Step | Result |
| --- | --- |
| `PATCH` the newest release with `{"make_latest":"false"}` | `/releases/latest` = **newest** (no effect) |
| `PATCH` the newest with `{"make_latest":"legacy"}` | `/releases/latest` = **newest** (worse: `legacy` hands the decision back to GitHub) |
| `PATCH` the older one with `{"make_latest":"true"}` | `/releases/latest` = **older** ✅ |
| publish a new release on top | the older designation is **cleared**, so it must be re-asserted on *every* release |

`"false"` is therefore the closest thing the API has to "none", and it is only
half the job: the pointer has to be re-stated somewhere. `finalize` does both,
in that order, and then reads the state back instead of trusting its own writes.

### What `finalize` guarantees

1. **Self-gating.** The shared flow does not re-export its outputs at the
   `workflow_call` level, so `releases_created` is unreadable and the job runs on
   every push. A release was cut by this push only if the manifest's tag points
   at this very commit; otherwise the job is a no-op. (`GET /releases/tags/{tag}`
   also answers 404 while the release is a draft, so the release id is read off
   the collection, with a bounded retry — the list can lag a few hundred ms
   behind a just-created release.)
2. **Signature.** The tag must be annotated and verify against the committed
   trust anchor, exactly as in the promotion gate. A hand-made or unsigned tag
   is not finalized.
3. **Publish, held off.** One PATCH, `{"draft": false, "make_latest": "false"}`,
   so the release never passes through a state where it is both public *and*
   `latest`. `prerelease` is read, never written: the badge stays as
   release-please set it. (This is what the PATCH guarantees; the window the
   shared flow opens *before* it is the accepted deviation below.)
4. **Re-assert the previous `latest`.** `PATCH {"make_latest": "true"}` on the
   release `capture` snapshotted. An empty snapshot is only legitimate on the
   first release — if other published releases exist, the job **fails** rather
   than guess.
5. **Verify.** `GET /releases/latest` is re-read and compared against the
   intended state; a mismatch fails the run. Every write above is idempotent, so
   a failed run is fixed by re-dispatching it.

`capture` runs in parallel with the shared flow and excludes the tag this push
is about to cut. That exclusion is what makes the snapshot correct in every
order: whether the release list is read before or after release-please created
the release, and whether this is the first attempt or a re-dispatch of it, the
answer is the release that was `latest` *before* this push. It is also why
`capture` never blocks the release: it hands over a hint, and `finalize` decides
what a missing hint means.

**Accepted deviation:** between the shared flow publishing the draft and the
PATCH in `finalize`, `latest` points at the new release for a few seconds.
Closing that window would mean taking over release creation or tag signing from
the shared template, which is out of scope by design — release-please keeps
doing what it does. If it ever stops being acceptable, the fix belongs in
`CI-CD-Templates` (`sign-tag`, where the tag is already in
`needs.release.outputs.tag_name`), and this job then reduces to the
re-assertion in step 4.

### The promotion gate

Promotion is guarded, in order: the tag exists, it is **annotated**, its
signature verifies against the committed trust anchor
([`.github/release-bot-gpg.pub`](../.github/release-bot-gpg.pub)), the release
is published, and it is not a pre-release. A tag that the `sign-tag` job did not
sign cannot be promoted, so the `latest` pointer can never drift onto a
hand-made or unsigned ref. Re-dispatching an already-promoted tag is a no-op, so
a half-failed promotion can simply be re-run.

The `isLatest` field it reads is GraphQL's, i.e. the server's own pointer, not a
local guess — which is why the workflow can tell "already promoted" from "needs
promoting" now that `finalize` deliberately leaves an *older* release holding
`latest`. Before `finalize` existed it had never run: its `isDraft` guard could
never pass while every release went public and `latest` on its own.

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
| Release publication | The release is published **off** `latest` by the local `finalize` job, and the `latest` that was in place before the push is re-designated on the previous release; only the manual `Release promote` workflow moves `latest` forward | `latest` is a human go/no-go tied to adoption, the same rule service releases follow. `make_latest=false` alone does **not** hold a release off `latest` — it stores no pointer and `GET /releases/latest` falls back to the newest published release — and the shared flow's tag force-publishes the draft on the way. See [Publishing a release](#why-the-release-cannot-be-held-off-latest-with-make_latestfalse) |
| Release pointer state | `latest` is an explicit server-side designation (`make_latest=true`) rather than a by-date fallback, and `finalize` re-asserts it on every release and verifies the result | A designation is what survives a new publication; the fallback always resolves to the newest release, which is exactly what a hold must not produce |
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
