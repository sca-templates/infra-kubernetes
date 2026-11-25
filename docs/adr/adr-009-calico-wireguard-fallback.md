# ADR-009: Calico + WireGuard fallback for Linkerd replacement

## Status

Accepted / implemented (2026-11-20). Opened the fallback branch defined by
[ADR-008](adr-008-cni-native-mtls.md) after the Cilium D2 gate failed. Linkerd
was removed in D4 and D5 closed the documentation; this ADR remains the record
of the selected Calico fallback.

## Context

ADR-008 selected Cilium + WireGuard as the primary replacement and required a
two-node evidence gate before any cutover. The Cilium PoC was iterated through
seven runs. Harness defects were fixed first: cgroup v1 on the WSL2 host, chart
resolution through the OCI registry, Cilium 1.20 routing keys, Helm readiness,
and the non-shared `/sys/fs/bpf` mount. Cilium then installed cleanly and both
nodes reached `Ready`.

D2 still failed. Attempt 6 reached Service DNS resolution before any cross-node
request; attempt 7 used the server pod IP directly with native routing and
`autoDirectNodeRoutes`. The request timed out after 10s. Cilium reported
`Encryption: Wireguard` with `Port: 51871` and `Peers: 1` on both nodes, but
`cilium_wg0` counters stayed at zero and no handshake was observed. Host routes
to the remote pod CIDR were present on both nodes. Tunnel and native routing
were both exercised, so the remaining failure is the Cilium datapath on this
Docker/WSL2 substrate, not the chart pin, Helm wiring, or WireGuard key setup.

ADR-008 line 103 states that a D2 failure opens the Calico fallback amendment.
This ADR is that amendment.

D2-Calico attempt 1 failed before CNI readiness: Calico `v3.31.7` renders the
`ebpf-bootstrap` init container unconditionally, and its bidirectional `/sys/fs`
mount is rejected by the WSL2/Docker substrate. The harness now removes that
init container and its BPF-only mounts and volumes from the pinned manifest;
this PoC uses the iptables dataplane and needs no eBPF. This is a substrate
compatibility finding, not a WireGuard result.
D2-Calico attempt 2 then failed creating the main `calico-node` container:
WSL2 has no `/sys/kernel/security`, and kubelet could not create the hostPath
(`failed to mkdir "/sys/kernel/security": operation not permitted`). The harness
now also removes that mount and volume; Felix treats an unreadable lockdown
file as not locked down, so this does not affect the iptables/VXLAN dataplane.
D2-Calico attempt 3 brought both nodes to `Ready` and reached the cross-node
HTTP check, but the verifier called `wg show` inside `quay.io/calico/node`,
which does not ship the `wg` CLI. This is a harness defect, not a WireGuard
result. The gate now enables Felix WireGuard Prometheus metrics and reads
peer, handshake and byte counters from `hostNetwork` pods using the already
pinned curl image.
D2-Calico attempt 4 confirmed the config keys but showed that patching
`FelixConfiguration` after the `calico-node` rollout is too late: Felix calls
`ConfigurePrometheusMetrics` at startup and registers the WireGuard collector
only when `wireguardEnabled` is already true. `/metrics` answered, but no
`wireguard_*` series existed. The harness now patches `FelixConfiguration`
before waiting for the rollout and forces a `calico-node` restart to avoid the
DaemonSet creation race; the gate requires `wireguard_meta` before checking
peer keys.
D2-Calico attempt 5 registered the collector and passed the `wireguard_meta`
readiness check, but the evidence scrape ran within Felix's one-second
WireGuard collection rate limit and captured an empty series. The gate now
retries WireGuard scrapes until a `wireguard_meta` sample is present before
capturing and validating the evidence.

## Decision

Evaluate Calico `v3.31.7` + WireGuard as the CNI replacement using a disposable
two-node k3s-in-Docker PoC. The candidate is pinned to
`https://raw.githubusercontent.com/projectcalico/calico/v3.31.7/manifests/calico-vxlan.yaml`
with VXLAN `Always`, IPIP `Never`, pod CIDR `10.244.0.0/16`, MTU `1440`, and
`IP_AUTODETECTION_METHOD=interface=eth0`. WireGuard is enabled through
`FelixConfiguration`, not through `calicoctl`.

The D2-Calico gate requires: both nodes Ready; Calico pods Ready;
`projectcalico.org/WireguardPublicKey` present on both nodes; `wireguard.cali`
with one peer and a recent handshake on both nodes increasing transfer
counters; a cross-node pod-IP HTTP request succeeding; and scratch cluster
removed. The evidence must state that Calico encrypts only the host-to-host leg;
pod-to-host traffic and same-node pod traffic remain plaintext. WireGuard is
authenticated L3/L4 transport, not workload mTLS, SPIFFE identity, or Linkerd
L7 retries/timeouts/traffic split.

If D2-Calico fails on this substrate, stop the migration and report the
substrate limitation. Do not substitute IPsec, silently keep Linkerd, or start
the D3/D4 cutover without a passing D2 gate.

## Result

D2-Calico passed on 2026-11-17. Both nodes reached `Ready`, cross-node pod-IP
HTTP succeeded, and Felix metrics showed `wireguard.cali` with one peer on each
node, a recent handshake and positive `wireguard_bytes_sent` and
`wireguard_bytes_rcvd`. The scratch cluster was removed; evidence is under
`.generated/calico-wireguard-evidence/`. D3 proceeded, D4 removed Linkerd and
D5 closed the documentation.

## Consequences

- A new pinned PoC harness lives under `poc/calico-wireguard/`; the Cilium PoC
  stays as the failed primary-candidate evidence.
- D3 landed after the passing D2-Calico gate; D4 removed Linkerd and D5 closed
  the documentation.
- The selected CNI becomes bootstrap-managed substrate in D3, with per-env
  pinned profiles and a documented rollback.
- Services lost per-workload identity, service-mesh golden signals and L7
  traffic management; any future requirement needs a separate ADR.
- Same-node pod traffic is never encrypted, and the pod-to-host leg under
  Calico remains plaintext.

## Implementation plan

| Checkpoint | Scope | Gate |
| --- | --- | --- |
| D2-Calico | Add the pinned Calico WireGuard PoC harness and run it on a fresh two-node cluster | D2-Calico evidence gate above |
| D3 | Land the chosen CNI as bootstrap-managed substrate with per-env pinned profiles, preflight checks, CI path filters and substrate smoke; keep Linkerd deployed | Fresh local substrate reaches full platform health with the new CNI and a documented rollback |
| D4 | Remove Linkerd CRDs, control plane, identity PKI, smoke targets, Vault allowlist exception, service-template annotation and repository wiring | No Linkerd runtime or ArgoCD references remain |
| D5 | Documentation closeout: update status/catalog/roadmap and mark ADR-008 and this ADR implemented | Docs match the deployed platform |

D5 closed the documentation: ADR-008 and this ADR were marked implemented,
current-state docs were aligned with the D4 removal, `observability-radar.md`
was scoped to native targets, and the Work Log records the closure.

## D3 implementation

D3 landed the selected CNI as **bootstrap substrate**, not as a catalog
component: `bootstrap/cni-emulator.sh` installs a pinned
`registry.k8s.io/kube-proxy:v1.34.1` DaemonSet first with
`--conntrack-max-per-core=0` (the WSL2 host makes `/proc/sys/net/netfilter` read
only), probes `kubernetes.default.svc` before continuing, points Calico at the
real API endpoint via `kubernetes-services-endpoint`, then applies a checksum-verified
Calico `v3.31.7` VXLAN manifest (iptables dataplane, WireGuard, `MTU=1440`,
`interface=eth0`, eBPF/securityfs mounts stripped as in D2). Floci starts with
`FLOCI_SERVICES_EKS_DISABLE_CNI=true` and `rancher/k3s:v1.34.1-k3s1` (the
`--kubernetes-version` passed to `create-cluster` is `1.34`), so no CNI image
floats to `latest`. The `1.35` pin was reverted because kubelet `1.35` refuses
to start on the cgroup v1 WSL2 host; real EKS nodes run cgroup v2 and are
unaffected. Profiles live in `envs/<env>/cni.yaml`: `local` is enforced by the
preflight; `dev`/`qa`/`prod` record the external-cluster contract until those
clusters are managed outside Floci. `bootstrap/smoke-cni.sh` (`make smoke
COMPONENT=cni`) runs before `make bootstrap` on every smoke and gates on both
DaemonSets, `FelixConfiguration/default`, per-node WireGuard public keys,
Felix metrics over `hostNetwork` (WireGuard interface metrics only where peers
exist), and pod-to-pod HTTP. CI resolves CNI
changes via `pr-cluster.yml`, and `validate.yml` kubeconform/kube-lints
`bootstrap/cni/manifests/*.yaml`.

### Local gate (user-run)

```bash
make eks-up
make smoke COMPONENT=cni
make bootstrap ENV=local
make validate
make smoke COMPONENT=cert-manager
make smoke COMPONENT=eks
```

The gate passes only when the fresh single-node substrate reaches full platform
health with the bootstrap-managed CNI and `smoke-cni.sh` reports
`[OK] smoke(cni)`. On 2026-11-20 the full gate passed: `make eks-up` reached node
`Ready`, `make smoke COMPONENT=cni` reported `[OK] smoke(cni)`, `make bootstrap
ENV=local` + `make validate` converged 13 local Applications
`Synced`/`Healthy` on `feature/decisions` with the optional messaging tier
enabled, and the component smoke sweep was green. On `main`, where that tier is
absent, the catalog has 11 Applications and `nats`/`nack` report `[SKIP]`.
Multi-node peer/handshake evidence remains the D2 gate and is not re-run here.
The first full attempt failed at ArgoCD's `argocd-redis-secret-init` pre-install
hook because D3's own kube-proxy crashed on `nf_conntrack_max: permission
denied`, leaving ClusterIP routing down; `--conntrack-max-per-core=0` and the
internal API probe above closed that gap without a rollback.

### Rollback

There is no in-place flip between dataplanes. Revert the D3 change and run
`make eks-down`; the next `make eks-up` restores Floci's bundled
Flannel/kube-proxy. Update `docs/status.md` and this ADR to record the rollback
instead of patching forward.
