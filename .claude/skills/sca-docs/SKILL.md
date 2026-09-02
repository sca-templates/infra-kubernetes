---
name: sca-docs
description: Enforce sca-docs conventions when writing or updating this repository's documentation (README.md, docs/, AGENTS.md). Use when the user asks to create, edit, or review documentation.
---

# sca-docs conventions

> Reference: <https://github.com/sca-templates/sca-docs>

## Rules (strict)

1. **English only** — all content, commit messages, PR descriptions.
2. **One fact, one place** — depth in this repo's `docs/`, topology in the
   vault, pointers in READMEs. Never duplicate a fact across files.
3. **Source of truth = `docs/`.** From Phase 1, phase prompts read
   `docs/INDEX.md` → `docs/status.md` + `docs/architecture.md` first, execute
   against their gates, and update those files (plus the roadmap Work Log) in
   the same commit that lands a component. Docs move with their code.
4. **Truth over aspiration** — never list an un-deployed component as
   deployed. Use explicit `planned (Phase N)` / `deployed` Status values (see
   `docs/architecture.md`). What is not in the catalog or status does not exist.
5. **Reference-and-explain** — point at real files; do not copy whole
   manifests (duplication caused the historical drift). External links
   (GitHub/sca-docs) as raw URLs, no local checkout assumed.
6. **Environment gradient** — document `local → dev → qa → prod` explicitly
   with each environment's profile and sync policy (see `docs/architecture.md`).
7. **Links** — relative markdown links between `docs/` files and to the repo
   root; wikilinks `[[…]]` only inside the vault, never here.
8. **Roadmap Work Log** — every phase that lands appends its row (phase,
   component, gate result, commit) so the roadmap records reality, not intent.

## Definition of done

- [ ] Content in English
- [ ] No duplicated facts (cross-links instead)
- [ ] Status values truthful (`planned` vs `deployed`), updated in the landing commit
- [ ] Roadmap Work Log appended for landed components
- [ ] Environment gradient documented where relevant
- [ ] `make validate-static` passes (markdownlint, YAML parse, bash -n)

## Fetch conventions

Consult sca-docs via raw URLs:
`https://raw.githubusercontent.com/sca-templates/sca-docs/main/<path>`
