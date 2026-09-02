# CLAUDE.md — repo-specific guidance

## Authority

**AGENTS.md is authoritative for this repository.** It is the rules of
engagement (environment model, component catalog with status, sync-waves,
conventions, commands, troubleshooting). Read it first, then
[docs/INDEX.md](docs/INDEX.md).

## CodeGraph

This repository may be indexed by
[CodeGraph](https://github.com/aaronleopold/codegraph). If a `.codegraph/`
directory exists at the repo root, use it before grepping/reading when you need
to understand this repo's YAML/Shell/JSON: `codegraph explore "<question>"`, or
the CodeGraph MCP tool when available. If there is no `.codegraph/`, skip
CodeGraph — the user opts in.

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
