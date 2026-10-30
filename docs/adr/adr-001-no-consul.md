# ADR-001: No in-cluster Consul

## Status

Accepted

## Context

The platform initially considered Consul for service discovery and configuration. However, Kubernetes provides native DNS for service discovery, and we need to evaluate service mesh needs separately.

## Decision

Do not deploy Consul in-cluster. Use native Kubernetes DNS for service discovery. Service mesh capabilities will be evaluated separately (initially Linkerd, now migrating to CNI-native mTLS).

## Consequences

- Simpler architecture, fewer components to operate
- Native Kubernetes service discovery is sufficient
- Service mesh (Linkerd) provides mTLS separately from service discovery
- Avoids operational overhead of Consul cluster management
