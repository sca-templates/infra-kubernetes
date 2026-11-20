# Project: Implement Linkerd control plane (removed in D4)

Area: Edge & Mesh · Wave 30 · Environments: local→dev→qa→prod · Historical record
Depends on: linkerd-crds (#9) — CRDs must be present first. Deployed as a
**dedicated ArgoCD Application** per env (`argocd/linkerd-<env>.yaml`, chart
`linkerd/linkerd-control-plane`), **not** by the `linkerd install` script: the CI
cluster smoke discovers the catalog from `infrastructure/*/` and requires every
entry to be an ArgoCD `Application` `<name>-<env>` that converges — the script
model cannot be validated (same reasoning as Kong; see the deviations log in
[docs/architecture.md](../architecture.md#deviations-log)).
Project done when: control-plane Deployments `Ready`; the identity chain is valid
(the issuer chains to the trust anchor the proxies trust); the mesh carries
traffic end-to-end for an injected workload (real HTTP request, live identity
leaves, inbound+outbound success metrics).

## Milestone M1 — Control plane

M1 done when: control-plane Deployments `Ready` + identity chain valid + webhooks
wired.

- [ ] Issue #14 · Install Linkerd control plane (dedicated Application)
  Depends on: linkerd-crds (#9)
  - [x] `infrastructure/linkerd/` values + manifests (identity PKI) + per-env
        overlays; dedicated `argocd/linkerd-<env>.yaml` wave 30
        - Commits: `feat(linkerd): control plane as a dedicated Application`
  - [x] identity PKI in-cluster: cert-manager issues the issuer; the committed
        root CA anchors the chain (trust-roots ConfigMap + CA Issuer)
        Commits: `feat(linkerd): identity PKI via cert-manager`
  - [x] smoke: Deployments Ready + identity chain (`openssl verify` anchor→issuer)
        + 3 admission webhooks wired + identity-leaf clock/TTL preflight
        + data plane end-to-end (injected nginx/curl workload, HTTP 200, live
        identity leaves, inbound+outbound success)
        Commits: `test(linkerd): control plane and identity smoke`
  - [x] docs: Work Log row + catalog Status → deployed
        Commits: `docs(linkerd): mark deployed`
  Issue done when: `make smoke COMPONENT=linkerd` green + catalog Status deployed.

## Retirement (ADR-008)

D0 research is complete (2026-11-17): [ADR-008](../adr/adr-008-cni-native-mtls.md)
proposes replacing the mesh with CNI-managed WireGuard transport encryption.
D1 added the disposable [Cilium PoC harness](../../poc/cni-mtls/README.md); D2
ran it seven times and failed the cross-node gate, so
[ADR-009](../adr/adr-009-calico-wireguard-fallback.md) opened the Calico
fallback with the [Calico PoC harness](../../poc/calico-wireguard/README.md),
whose D2 gate passed on 2026-11-17 with cross-node HTTP and WireGuard
peer/handshake/counter evidence on both nodes. D3 now lands the bootstrap-managed
CNI substrate (Calico + WireGuard + pinned kube-proxy, per-env profiles and a
single-node smoke); its fresh-cluster substrate gate and the full platform gate
passed on 2026-11-20. D4 removed the control plane and every wiring surface
inventoried in [migration-inventory-phase-a.md](../migration-inventory-phase-a.md);
D5 closed the docs. Do not describe WireGuard as workload mTLS: ADR-008 records
the identity and L7 trade-offs. The D4 Work Log row records the repository and
local-cluster cleanup.

No natural further phases under M1 → the retirement checkpoints are tracked by
ADR-008, ADR-009 and the global Work Log.
