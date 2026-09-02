---
description: Full platform bootstrap — prereqs, kind cluster, ArgoCD and the root Application.
agent: build
---

# Bootstrap

Run `make prereqs && make cluster-up && make bootstrap` from the repo root
and report the result. `prereqs` installs the pinned toolchain (kubectl, helm,
kind), `cluster-up` creates the kind cluster, `bootstrap` installs ArgoCD and
applies the root Application for `$ENV` (default `local`). ArgoCD then syncs
every component in sync-wave order — watch with `make status`. On failure, use
the `platform-lifecycle` skill to isolate the stage before retrying.
