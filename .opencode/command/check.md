---
description: Run the static validation suite only (no cluster needed) and summarize failures.
agent: build
---

# Check

Run `make validate-static` from the repo root and report the result:
`markdownlint` over all Markdown, YAML parse over every manifest, yamllint
when installed locally, and `bash -n` over `bootstrap/*.sh`. Fix any failure
in place and re-run until green — CI enforces the same checks on every PR.