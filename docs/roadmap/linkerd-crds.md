# Project: Implement linkerd-crds (removed in D4)

Area: Edge & Mesh · Wave -10 · Environments: local→dev→qa→prod · Historical record
Depends on: — (CRDs install before the control plane, wave -10)
Project done when: linkerd CRDs present in the cluster and amAlive; control
plane (project #14) installs cleanly against them.

No natural phases → issues directly under the project.

- [x] Issue #9 · Deploy `linkerd/linkerd-crds`
  Depends on: —
  - [x] `infrastructure/linkerd-crds/` values-base + overlays for 4 envs
        - [x] envs/local, dev, qa, prod
        - Commits: `feat(linkerd-crds): add chart reference and per-env overlays`
  - [x] registry appset element (wave -10)
        Commits: `feat(linkerd-crds): register in apps appset (wave -10)`
  - [x] smoke: `kubectl get crd` shows the linkerd groups
        Commits: `test(linkerd-crds): crd presence smoke`
  - [x] convergence: appset `ignoreDifferences` extended for server-defaulted CRD fields; stale pre-restart Linkerd CRDs cleaned on local
        Commits: `fix(linkerd-crds): ignore apiserver-defaulted CRD fields`
  - [x] docs: Work Log row + catalog Status → deployed
        Commits: `docs(linkerd-crds): mark deployed`
  Issue done when: linkerd CRDs installed, control plane installs against them.

## Retirement (D4)

D4 removed `infrastructure/linkerd-crds/`, `envs/<env>/linkerd-crds.yaml`,
`argocd/linkerd-crds-<env>` from the ApplicationSets and the CRD-only smoke after
the Calico WireGuard D2/D3 gates. The CRDs remain in a long-lived local cluster
until the one-time ArgoCD Application cleanup; the Work Log row records the
rollback.
