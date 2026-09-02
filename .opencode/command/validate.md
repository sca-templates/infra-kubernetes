---
description: Run the full validation suite — static checks plus live cluster checks.
agent: build
---

# Validate

Run `make validate` from the repo root and report the result. This is the
static suite (markdownlint, YAML parse, `bash -n`, yamllint when installed)
plus live cluster checks (ArgoCD apps Synced/Healthy, pods healthy). If the
cluster is not up, run `make validate-static` instead and say so. On failure,
use the `platform-lifecycle` skill to isolate, fix, then re-run.