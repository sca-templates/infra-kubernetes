# ADR-002: Replace Linkerd with CNI-native mTLS

## Status
Proposed

## Context
Linkerd provides service mesh capabilities including mTLS, observability, traffic management (retries, timeouts, traffic splits), and ServiceProfiles. However, sidecar proxies add overhead (CPU/RAM). Modern CNI plugins (Cilium, Calico) can provide mTLS at L3/L4 using WireGuard or IPsec with lower overhead.

## Decision
Replace Linkerd service mesh with CNI-native mTLS. Use Cilium or Calico with WireGuard/IPsec encryption. Accept loss of L7 traffic management features (retries, timeouts, traffic splits, ServiceProfiles) in exchange for reduced resource consumption.

## Consequences
- Reduced resource consumption (no sidecar containers)
- Simpler architecture
- Loss of L7 observability and traffic control features
- Must implement NetworkPolicies carefully
- Observability relies more on Kube-Prometheus/Loki/Tempo
- Requires thorough testing in all environments

## Implementation
- PoC in Floci before production
- Remove linkerd-crds and linkerd-control-plane
- Remove linkerd.io/inject annotations
- Configure CNI with encryption enabled
