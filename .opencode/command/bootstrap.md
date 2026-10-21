---
description: Full platform bootstrap — prereqs, Floci EKS cluster, ArgoCD and the root Application.
agent: build
---

# Bootstrap

Run `make prereqs && make eks-up && make bootstrap` from the repo root
and report the result. `prereqs` installs the pinned toolchain (kubectl, helm),
`eks-up` boots the Floci emulated EKS substrate (a real single-node k3s node)
and points kubectl at it, and `bootstrap` installs ArgoCD, seeds the catalog
wiring (`argocd/apps-${ENV}.yaml` + `argocd/kong-${ENV}.yaml`) with the
`{{GIT_REPO_URL}}`/`{{GIT_TARGET_BRANCH}}` placeholders resolved and applies the
root Application (default `$ENV=local`, which has no root app). ArgoCD then syncs
every component in sync-wave order — watch with `make status`. On failure, use
the `platform-lifecycle` skill to isolate the stage before retrying.
