# Project: Implement Linkerd control plane

Area: Edge & Mesh · Wave 30 · Environments: local→dev→qa→prod
Depends on: linkerd-crds (#4) — CRDs must be present first; installed by script
(`linkerd install`), not an ArgoCD Application.
Project done when: control plane pods `Running`; `linkerd check` shows
golden signals; mTLS identity works for the mesh namespace.

## Milestone M1 — Control plane

M1 done when: pod `Running` + `linkerd check` clean + mTLS identity ok.

- [ ] Issue #9 · Install Linkerd control plane (script)
  Depends on: linkerd-crds (#4)
  - [ ] `infrastructure/linkerd/` install script + overlay config
        - Commits: `feat(linkerd): control plane install script`
  - [ ] golden signals config (identity, proxy-init)
        Commits: `feat(linkerd): golden signals configuration`
  - [ ] smoke: `linkerd check` no errors; pod identity via `kubectl get` annotations
        Commits: `test(linkerd): check and identity smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(linkerd): mark deployed`
  Issue done when: `linkerd check` clean + mTLS identity confirmed.

No natural further phases → issues stay under M1.
