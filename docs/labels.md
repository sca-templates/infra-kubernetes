# Labels

The repository's label model is deliberately small. Groups, waves and status
live on the Kubernetes Planning board as **native fields** — not as labels —
so an issue stays grouped even when its labels are stripped. Labels only carry
what the field model cannot: cross-cutting categories and CI/CD context.

## Model: board fields carry structure

| Board field | Values | Purpose |
| --- | --- | --- |
| `Domain` | Security & Identity · Edge & Mesh · Data · Observability · Delivery & Resilience | component group |
| `Wave` | −20 … 80 (integers ≥10 apart) | sync-wave of the component |
| `Status` | New · Needs triage · … · Deployed | delivery lifecycle |
| `Priority` · `Effort` · `Team` | native single-selects | planning knobs |

Migration rationale: the previous `domain:*` / `wave:*` / `type:*` labels
duplicated these fields and made PR labelling cumbersome. Values were
backfilled into the native fields before the labels were removed, so the board
grouping in `docs/roadmap.md` is unchanged ([roadmap](roadmap.md)).

## Label set (the only labels that exist)

| Label | Color | Purpose |
| --- | --- | --- |
| `bug` · `enhancement` | #d73a4a · #a2eeef | issue templates (`bug_report.yml`, `feature_request.yml`) |
| `good first issue` | #7057ff | beginner-friendly task |
| `ci/cd` | #8250df | CI/CD bumps and pipeline changes (manual) |
| `feature` · `ci` · `refactor` | — | created automatically by the auto-labeler (`shared-auto-label`): `feat*` → `feature`, `ci*`/`build*` titles and `.github/workflows` / `.github/actions` files → `ci`, `refactor*` → `refactor` |
| `security` | #5319e7 | security work (crypto, RBAC, secret flow); also applied automatically on `security*` titles, `SECURITY.md` / `security/*` changes and vulnerability hints |
| `data` · `edge` · `observability` · `delivery` | — | flat component-group tags (short names, no prefix) |
| `accessibility` · `documentation` · `duplicate` · `help wanted` · `invalid` · `question` · `wontfix` | — | GitHub defaults, kept for triage |
| `dependencies` · `github_actions` | — | created automatically by Dependabot |
| `autorelease: pending` · `autorelease: tagged` | — | created automatically by release-please |

## Rules

- Use labels only when they add cross-cutting value to a pull request or
  issue; structural grouping (`Domain`, `Wave`, `Status`) goes on the board,
  never in labels.
- Do not create prefixed taxonomies (`domain:*`, `wave:*`, `type:*`, …). This
  repo resolved that model away on `main` (2026-09-05); a new label needs a
  PR to `docs/labels.md` explaining why one of the existing labels does not
  fit.
- Bot-created labels (Dependabot, release-please, the auto-labeler) are owned
  by their owner and must not be manually recreated or renamed. The
  auto-labeler contributes `feature`, `ci` and `refactor` (and re-applies the
  existing `bug`/`enhancement`/`documentation`/`security`/`dependencies`).
- `ci/cd` marks automation bumps (Workflow bumps, release-please tweaks,
  pin updates); a component change that merely *runs* through CI does not get
  it. The labeler's `ci` (type) and a manual `ci/cd` (automation bump)
  overlap on workflow PRs; labels are never removed, so one does not replace
  the other.
