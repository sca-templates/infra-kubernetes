# Cilium WireGuard transport-encryption PoC

Scope: D1 of [ADR-008](../../docs/adr/adr-008-cni-native-mtls.md). This is a
disposable experiment harness only. It does not change the platform catalog,
ArgoCD wiring, `Makefile`, `bootstrap/`, or the deployed Linkerd mesh.

WireGuard encrypts authenticated traffic between Cilium-managed endpoints on
different nodes. It is node-to-node transport encryption at L3/L4, not
workload mTLS, and same-node pod traffic stays plaintext by design.

## Pins

| Component | Pin |
| --- | --- |
| Cluster nodes | `rancher/k3s:v1.37.2-k3s1` |
| Cilium Helm chart | `1.20.5` from `https://helm.cilium.io` |
| Cilium agent and operator | `v1.20.5` (`quay.io/cilium/cilium`, `quay.io/cilium/operator`) |
| Smoke server | `nginxinc/nginx-unprivileged:1.27-alpine` |
| Smoke client | `curlimages/curl:8.10.1` |

All pins live in [versions.env](versions.env) and
[cilium-values.yaml](cilium-values.yaml). Override them only for a new reviewed
pin; never use a floating tag.

## Prerequisites

- Docker with permission to run privileged containers.
- The repository-pinned `kubectl` and `helm` (`make prereqs`).
- `openssl` and `jq`.
- Kernel WireGuard support on the Docker host. On cgroup v1 hosts, `up.sh`
  passes `fail-cgroupv1=false` to both kubelets; this PoC-only override keeps
  Kubernetes `1.37` runnable there and is not a platform cgroup guarantee.

## Run

```bash
poc/cni-mtls/up.sh
poc/cni-mtls/smoke.sh
```

`up.sh` creates a two-node k3s cluster in namespace-local Docker resources,
writes a private kubeconfig under `.generated/cni-mtls/`, installs Cilium with
WireGuard, and waits for both nodes to become Ready. It does not touch
`$KUBECONFIG`.

`smoke.sh` pins the HTTP server to the agent node and the client to the server
node, performs a real cross-node request, then checks Cilium WireGuard status
and a recorded handshake on both nodes. Expected markers:
`CNI_MTLS_SMOKE_OK`, `Encryption: Wireguard`, `Port: 51871`, and `Peers: 1`.

For the D2 capture evidence, inspect the `cilium_wg0` interface or UDP `51871`
on both nodes while the smoke request is running, then record the result in the
ADR-008 evidence checkpoint.

## Cleanup

```bash
poc/cni-mtls/down.sh
```

`down.sh` removes only the named PoC containers, Docker network and generated
state. It never modifies the Floci EKS substrate or any platform namespace.
