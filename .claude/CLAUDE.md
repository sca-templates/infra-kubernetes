# CLAUDE.md — repo-specific guidance

## Authority

**AGENTS.md is authoritative for this repository.** It is the rules of
engagement (environment model, component catalog with status, sync-waves,
conventions, commands, troubleshooting). Read it first, then
[docs/INDEX.md](docs/INDEX.md).

<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->

## Authority

Read **AGENTS.md**, **docs/roadmap.md** (delivery plan) and
**docs/status.md** (current state) — they are authoritative for this repository.
`docs/INDEX.md` is the entry point to the knowledge base.

## Working here

- **The user commits and pushes — never execute `git commit`, `git push`, or
  any other git write on your own.** Draft commits/messages freely, but do not
  stage, reset, amend or otherwise mutate git history without explicit,
  current authorization from the user.
- This repo is **GitOps source of truth for the `sca` platform**. It is a
  template: no external local paths, sibling knowledge is an external link.
- From Phase 1, `docs/` **is the source of truth**: read
  `docs/INDEX.md` → `docs/status.md` + `docs/architecture.md` before any
  phase work, and update them in the same commit that lands a component.
- Repo language is English; nothing is deployed by hand after `make bootstrap`.
- Never commit secrets: `.env`, `.secrets/`, kubeconfigs, tokens.
