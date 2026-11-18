# Calico + WireGuard CNI PoC

Scope: D2 fallback of [ADR-009](../../docs/adr/adr-009-calico-wireguard-fallback.md), opened after the Cilium primary gate failed in [ADR-008](../../docs/adr/adr-008-cni-native-mtls.md). This harness is disposable and never becomes a catalog component. It creates a two-node k3s-in-Docker cluster, installs pinned Calico with VXLAN, enables WireGuard through `FelixConfiguration`, and removes the cluster on teardown.

## Pins

| Item | Pin |
| --- | --- |
| k3s | `rancher/k3s:v1.37.2-k3s1` |
| Calico manifest | `v3.31.7` from `https://raw.githubusercontent.com/projectcalico/calico/v3.31.7/manifests/calico-vxlan.yaml` |
| VXLAN | `Always` |
| IPIP | `Never` |
| Pod CIDR | `10.244.0.0/16` |
| MTU | `1440` |
| WireGuard port | UDP `51820` |
| Server workload | `nginxinc/nginx-unprivileged:1.27-alpine` |
| Client workload | `curlimages/curl:8.10.1` |

Override pins only for a reviewed pin change; never use a floating tag.

## Run

```bash
mkdir -p .generated/calico-wireguard-evidence
poc/calico-wireguard/down.sh 2>&1 | tee .generated/calico-wireguard-evidence/d2-down-before.log
poc/calico-wireguard/up.sh 2>&1 | tee .generated/calico-wireguard-evidence/d2-up.log
poc/calico-wireguard/smoke.sh 2>&1 | tee .generated/calico-wireguard-evidence/d2-smoke.log
poc/calico-wireguard/down.sh 2>&1 | tee .generated/calico-wireguard-evidence/d2-down.log
```

`up.sh` patches the pinned manifest before apply: `veth_mtu: 1440`, pod CIDR `10.244.0.0/16`, VXLAN `Always`, `IP_AUTODETECTION_METHOD=interface=eth0`, and `allow_ip_forwarding` in the CNI config. It also strips the unconditional `ebpf-bootstrap` init container and its BPF-only mounts and volumes, plus the `sys-kernel-security` mount absent from WSL2; this PoC uses the iptables dataplane and does not need eBPF or kernel-lockdown detection. It waits for `daemonset/calico-node`, patches `felixconfigurations.crd.projectcalico.org/default` with `wireguardEnabled: true`, and waits for both nodes to be `Ready`.

## Gate

`smoke.sh` passes only when all of these hold:

- nginx runs on the agent node and curl runs on the server node.
- Cross-node HTTP to the server pod IP returns the nginx welcome page.
- Both nodes publish `projectcalico.org/WireguardPublicKey`.
- Felix `wireguard_meta` reports `wireguard.cali` with each node's public key.
- `wireguard_latest_handshake_seconds` reports the other node's public key as the only peer, with a handshake within the last 10 minutes.
- `wireguard_bytes_sent` and `wireguard_bytes_rcvd` are both positive after the request.

`up.sh` enables Felix Prometheus metrics on port `9091` and restarts the `calico-node` DaemonSet so Felix starts with `wireguardEnabled` already true. Felix registers the WireGuard collector only at startup, so applying the patch after rollout leaves `/metrics` available but without any `wireguard_*` series. Felix also rate-limits WireGuard metric collection to one second, so `smoke.sh` retries a scrape until `wireguard_meta` is present before parsing it. `smoke.sh` creates temporary `hostNetwork` pods from the pinned curl image on both nodes to read `/metrics`, then removes them. The Calico node image does not include the `wg` CLI; Felix exposes the same peer, handshake and counter evidence through metrics.

Evidence files are written to `.generated/calico-wireguard/<node>-wireguard.txt`. Because `down.sh` removes that directory, copy any needed evidence into `.generated/calico-wireguard-evidence` before teardown.

## Scope limits

Calico WireGuard encrypts only the host-to-host leg of inter-node pod traffic. The pod-to-host leg stays plaintext, and same-node pod traffic is never encrypted. WireGuard is authenticated L3/L4 transport, not workload mTLS, SPIFFE identity, or Linkerd L7 retries/timeouts/traffic split. A passing gate authorizes D3 planning only; it does not remove Linkerd.
