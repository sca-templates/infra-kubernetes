# ADR-002: Linkerd CNI and mTLS

## Status

Superseded by [ADR-008](adr-008-cni-native-mtls.md) and closed by the D4 removal
(2026-11-20). This decision described the previously planned Linkerd CNI plugin,
which was never enabled: its values set `cniEnabled: false`, so the removed mesh
used the `proxy-init` init container. See ADR-008 for the accepted replacement
and [ADR-009](adr-009-calico-wireguard-fallback.md) for the selected Calico
fallback.

## Context

Default Linkerd installation uses init containers to configure iptables, requiring elevated privileges. This can conflict with security policies and certain cluster configurations.

## Decision

Use Linkerd CNI plugin for traffic redirection instead of init containers. Maintain Linkerd's mTLS capabilities for service-to-service encryption.

## Consequences

- Reduced privilege requirements (no NET_ADMIN in init containers)
- Better compatibility with Pod Security Standards and restrictive policies
- Requires installing Linkerd CNI before the control plane
- Slightly more complex installation order (CNI first, control plane after)

## Implementation

- PoC in Floci before production rollout
- Install `linkerd-cni` DaemonSet before `linkerd-control-plane`
- Follow Linkerd CNI documentation for compatibility matrix
