# ADR-001: No in-cluster Consul

## Status

Accepted

## Context

The platform initially considered Consul for service discovery and configuration. Kubernetes provides native DNS for service discovery, and service mesh needs were evaluated separately.

## Decision

Do not deploy Consul in-cluster. Use native Kubernetes DNS for service discovery. Service mesh capabilities were evaluated separately; Linkerd was removed in D4 in favor of bootstrap-managed CNI transport encryption ([ADR-008](adr-008-cni-native-mtls.md), [ADR-009](adr-009-calico-wireguard-fallback.md)).

## Consequences

- Simpler architecture, fewer components to operate
- Native Kubernetes service discovery is sufficient
- Linkerd formerly provided mTLS separately from service discovery; it was removed in D4 ([ADR-008](adr-008-cni-native-mtls.md), [ADR-009](adr-009-calico-wireguard-fallback.md))
- Avoids operational overhead of Consul cluster management
