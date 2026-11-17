# ADR-008: Replace Linkerd with CNI-native mTLS

## Status

Proposed (2026-11-17; D0 research complete, D1 PoC files added; evidence pending). Supersedes ADR-002 for the replacement plan; Linkerd remains deployed until the D3/D4 cutover.

## Context

The platform currently deploys `linkerd-crds` at wave -10 and the
`linkerd-control-plane` at wave 30 in every environment. D0 is a static
research checkpoint: it inventories the current surfaces, evaluates the
candidate replacements and defines the gates. It does not change cluster
state, ArgoCD wiring, chart pins or runtime manifests.

The D0 inventory found 49 tracked files outside `CHANGELOG.md` at the start of
the checkpoint: 33 runtime/wiring/tooling files and 16 docs/history files. The
runtime surfaces are:

- Four dedicated control-plane Applications (`argocd/linkerd-<env>.yaml`) and
  the `linkerd-crds` entry in each `argocd/apps-<env>.yaml`.
- `infrastructure/linkerd/`, `infrastructure/linkerd-crds/` and the eight
  `envs/<env>/linkerd{,-crds}.yaml` overlays.
- The service-template injection surface:
  `charts/service-template/templates/deployment.yaml`, `values.yaml` and
  `values.schema.json`.
- Bootstrap and CI tooling: `Makefile`, `bootstrap/versions.sh`,
  `bootstrap/smoke-linkerd.sh`, `bootstrap/smoke-linkerd-crds.sh`,
  `bootstrap/smoke-target.sh`, `.gitleaks.toml` and `.vscode/settings.json`.
- Documentation history in `README.md`, `AGENTS.md`, `docs/`, and
  `CHANGELOG.md`. ADR-001, ADR-002 and the completed Work Log rows stay as the
  historical record.

The static search found no service-owned `TrafficSplit`, `ServiceProfile` or
other Linkerd L7 policy manifests in this repository; the only workload-facing
use is the `linkerd.io/inject: enabled` annotation in the service template and
the smoke's scratch namespace. Service repositories are outside this repo, so
their current Linkerd dependencies cannot be certified from here.

The migration label "CNI-native mTLS" is shorthand, not a protocol claim.
WireGuard provides authenticated, encrypted transport between nodes; it does
not issue per-workload certificates, does not provide SPIFFE-style identity,
and is not TLS. Replacing Linkerd with WireGuard therefore preserves
cross-node transport encryption at L3/L4 but removes workload identity,
per-route policy and L7 telemetry. This distinction is a gate, not a naming
detail: the acceptance criteria must never claim equivalence to Linkerd mTLS.

The only local substrate is Floci's emulated EKS: a real single-node k3s
container. WireGuard tunnels protect inter-node traffic, so a single-node
cluster cannot prove that encryption works. A meaningful PoC needs a
disposable cluster with at least two nodes or an explicitly documented
substrate extension.

## Evaluation

| Option | Fit | Limits | D0 verdict |
| --- | --- | --- | --- |
| Cilium + WireGuard | Cilium is an eBPF CNI with native `NetworkPolicy` support; WireGuard creates one authenticated tunnel per node pair, publishes node public keys through `CiliumNode`, and encrypts traffic between Cilium-managed endpoints. Upstream documents UDP `51871`, kernel-mode WireGuard on every node and `cilium-dbg status`/`tcpdump -i cilium_wg0` validation. | Same-node pod traffic is plaintext by design; tunnel mode double-encapsulates pod traffic; node-to-node encryption is beta and opts out of control-plane nodes; no workload identity or L7 retries/timeouts/traffic split. Running a custom CNI on k3s requires `--flannel-backend=none` (and normally `--disable-network-policy`), so the emulator bootstrap seam is part of the PoC. | Primary D1 PoC candidate |
| Calico + WireGuard | Host-to-host transport encryption via `FelixConfiguration.wireguardEnabled`; mature `NetworkPolicy` engine and documented managed-EKS support for host-network traffic. | Only the host-to-host leg is encrypted; the host-to-pod leg is plaintext unless an attacker has root on the node. Requires WireGuard on every participating node and MTU review. Still no workload identity or Linkerd L7 behaviour. | Fallback if Cilium fails the D1/D2 gate |
| k3s Flannel `wireguard-native` | Smallest local change: `--flannel-backend=wireguard-native` with kernel WireGuard modules on all nodes. | Tied to the local k3s substrate, does not define the dev/qa/prod CNI, does not add workload identity or L7 features, and cannot be validated on the current single node. Flannel's IPsec backend is deprecated. | Not selected as the replacement |
| IPsec as a generic substitute | Encrypts transport without per-workload sidecars. | k3s Flannel IPsec is deprecated; keying and interoperability are heavier than WireGuard, and it has the same identity/L7 gaps. | Rejected |

Sources consulted: the [Cilium WireGuard guide](https://docs.cilium.io/en/stable/security/network/encryption-wireguard/), the [Calico pod-traffic encryption guide](https://docs.tigera.io/calico/latest/network-policy/encrypt-cluster-pod-traffic), and the [k3s basic network options](https://docs.k3s.io/networking/basic-network-options). The local `docs/` set remains the source of truth for this repository; the external sca-docs vault still describes Linkerd as the target mesh and is treated as historical context here.

## Decision

Proceed with a gated replacement of Linkerd by Cilium + WireGuard, using
WireGuard only for authenticated cross-node transport encryption. Do not
present the result as workload mTLS, and do not start the cutover before the
D2 evidence gate passes. No runtime or wiring changes land in D0.

The CNI is platform substrate, not a wave-ordered catalog Application: it must
exist before ArgoCD can reconcile workloads. D1 must confirm how the bootstrap
installs it on a fresh cluster without a live CNI swap. If the Cilium PoC
fails, evaluate Calico + WireGuard in a new ADR amendment; do not substitute
IPsec or silently keep Linkerd while calling the migration complete.

The accepted trade-offs are the loss of Linkerd workload identity and L7
retries/timeouts/traffic split, and the operational prerequisites of the CNI.
Phase 14 observability remains planned and D5 is documentation-only; no new
observability component is added by this migration.

## Consequences

- Cross-node pod traffic can be encrypted at L3/L4 without injecting proxies
  into every workload.
- Same-node traffic remains unencrypted; this is a WireGuard property, not a
  misconfiguration.
- Every node needs kernel WireGuard support and UDP `51871` reachability, and
  the chosen CNI must be installed before the platform workload layer.
- Services lose per-workload identity, Linkerd golden signals and L7 traffic
  management. Any future requirement for those features needs a separate ADR.
- A CNI change is disruptive: D1 and D2 use disposable clusters only, and D3
  must define the rollback path before touching the shared platforms.
- Documentation must stop describing Linkerd as the active mesh only at D4/D5;
  until then, `status.md` and `architecture.md` continue to report it deployed.

## Implementation plan

| Checkpoint | Scope | Gate |
| --- | --- | --- |
| D0 | Static inventory, option evaluation, this ADR and cross-linked docs | Documentation-only; no runtime or wiring change |
| D1 | Add reproducible PoC files: disposable multi-node substrate recipe, pinned Cilium release, values, smoke script and cleanup. No catalog, ArgoCD or Makefile cutover yet | Files review; all images/charts pinned, no `latest` |
| D2 | Run the PoC on a fresh disposable cluster with at least two nodes and record the evidence | CNI and workloads Ready; WireGuard peers/handshakes on both nodes; cross-node HTTP request succeeds and captures show traffic through `cilium_wg0`/UDP `51871`; same-node limitation recorded; scratch cluster removed. Failure stops the migration or opens the Calico fallback amendment |
| D3 | Land the chosen CNI as bootstrap-managed substrate with per-env pinned profiles, preflight checks, CI path filters and substrate smoke; keep Linkerd deployed | Fresh local substrate reaches full platform health with the new CNI and a documented rollback to the previous substrate |
| D4 | Remove Linkerd CRDs, control plane, identity PKI, smoke targets, Vault allowlist exception, service-template annotation and repository wiring | No Linkerd runtime or ArgoCD references remain; catalog count and sync-wave map updated; Linkerd smokes removed |
| D5 | Documentation closeout: remove Linkerd golden-signal assumptions from observability docs, update status/catalog/roadmap and mark ADR-008 implemented | Docs match the deployed platform; Work Log row records the cutover |

D1 added the [PoC harness](../../poc/cni-mtls/README.md): a disposable two-node
k3s Docker substrate, Cilium chart `1.20.5` with `kubeProxyReplacement: false`,
WireGuard enabled, a cross-node HTTP smoke and teardown. The PoC was not run in
D1; D2 owns the evidence and may still open the Calico fallback amendment.

D2 attempt 1 (2026-11-17) failed before Cilium install: k3s `v1.37.2` rejected
the host's cgroup v1 (`fail-cgroupv1=true` by default), so the kubelet exited
and the API never became stable. The later capture and smoke errors were only
cascading effects, and cleanup succeeded. The harness now passes
`fail-cgroupv1=false` to both kubelets; this is a substrate compatibility
finding, not a WireGuard result or grounds for the Calico fallback.
D2 attempt 2 got past cluster startup but Helm did not resolve chart
`cilium/cilium` `1.20.5` from `https://helm.cilium.io`, so Cilium never
installed and the later workload, capture and smoke failures were cascading.
The harness now installs the same pinned chart from
`oci://quay.io/cilium/charts/cilium`, the OCI method recommended by Cilium.
D2 attempt 3 pulled that OCI chart successfully but Helm validation rejected
the legacy `tunnel: vxlan` value, removed in Cilium 1.15; Cilium never
installed and the later workload errors were cascading. The PoC values now use
`routingMode: tunnel` with `tunnelProtocol: vxlan`, the current 1.20 keys, and
drop the ignored `encryption.devices` value; the D2 rerun is pending.

## D1 decisions and open questions

- The PoC substrate is a separate two-node k3s Docker cluster, not Floci. It
  starts with `--flannel-backend=none` and `--disable-network-policy`, keeps its
  own kubeconfig under `.generated/cni-mtls/`, and never becomes a catalog
  component.
- Cilium chart and agent/operator images are pinned to `1.20.5`; the chart is
  installed from OCI as recommended upstream. `routingMode: tunnel` with
  `tunnelProtocol: vxlan` preserves the overlay for the Docker substrate, and
  `kubeProxyReplacement: false` keeps this checkpoint scoped to networking and
  encryption.
- How the environment gradient is expressed once local is no longer Flannel,
  including dev/qa/prod profiles that are provisioned outside this repo, stays
  open for D3.
- How service repositories are notified to drop the injected annotation at D4
  stays open; this repo can change only the service template.
