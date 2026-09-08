# Project: Implement cert-manager

Area: Security & Identity · Wave -20 · Environments: local→dev→qa→prod
Depends on: — (installs with the appset / CRDs at wave -20)
Project done when: `sca-ca` ClusterIssuer `Ready`; a leaf Certificate is
signed and usable; TLS issuers are available to all namespaces.

No natural phases → issues directly under the project.

- [x] Issue #1 · Deploy `jetstack/cert-manager` (+ CRDs) and the `sca-ca` issuer
  Depends on: —
  - [x] `infrastructure/cert-manager/` values-base + overlays for 4 envs
        - [x] envs/local, dev, qa, prod
        - Commits: `feat(cert-manager): add chart reference and per-env overlays`
  - [x] registry appset element (wave -20)
        Commits: `feat(cert-manager): register in apps appset (wave -20)`
  - [x] issuer: self-signed bootstrap `sca-ca` ClusterIssuer
        Commits: `feat(cert-manager): sca-ca self-signed ClusterIssuer`
  - [x] smoke: request an in-namespace leaf Certificate and confirm `Ready`
        Commits: `test(cert-manager): leaf certificate smoke`
  - [x] docs: Work Log row + catalog Status → deployed
        Commits: `docs(cert-manager): mark deployed`
  Issue done when: ClusterIssuer `Ready` + leaf Certificate `Ready`.
