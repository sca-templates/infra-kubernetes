# Project: Implement linkerd-crds

Area: Edge & Mesh · Wave -10 · Environments: local→dev→qa→prod
Depends on: — (CRDs install before the control plane, wave -10)
Project done when: linkerd CRDs present in the cluster and amAlive; control
plane (project #9) installs cleanly against them.

No natural phases → issues directly under the project.

- [ ] Issue #4 · Deploy `linkerd/linkerd-crds`
  Depends on: —
  - [ ] `infrastructure/linkerd-crds/` values-base + overlays for 4 envs
        - [ ] envs/local, dev, qa, prod
        - Commits: `feat(linkerd-crds): add chart reference and per-env overlays`
  - [ ] registry appset element (wave -10)
        Commits: `feat(linkerd-crds): register in apps appset (wave -10)`
  - [ ] smoke: `kubectl get crd` shows the linkerd groups
        Commits: `test(linkerd-crds): crd presence smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(linkerd-crds): mark deployed`
  Issue done when: linkerd CRDs installed, control plane installs against them.
