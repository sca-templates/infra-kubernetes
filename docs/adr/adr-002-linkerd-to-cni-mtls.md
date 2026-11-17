# ADR-002: Linkerd CNI and mTLS

## Status

Superseded by [ADR-008](adr-008-cni-native-mtls.md) (2026-11-17; D0 research
complete, D1 PoC files added; evidence pending). This decision describes the previously planned Linkerd
CNI plugin, which was never enabled: `infrastructure/linkerd/values-base.yaml`
sets `cniEnabled: false`, so the deployed mesh uses the `proxy-init` init
container. Linkerd remains deployed until ADR-008's D3/D4 cutover.

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
