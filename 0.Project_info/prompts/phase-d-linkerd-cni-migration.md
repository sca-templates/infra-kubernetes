# Phase D: Linkerd → CNI with mTLS L3/L4

## Objective
Replace Linkerd service mesh with CNI-native mTLS (WireGuard/IPsec). Must do PoC in Floci first. Lose L7 features (retries, timeouts, traffic split, ServiceProfiles).

## Context
From Phase A. ADR-001 already discards Consul. This is disruptive.

## Tasks

### 1. PoC in Floci (MANDATORY)
- Choose CNI (Cilium or Calico) - evaluate both
- Deploy in local/Floci environment
- Enable WireGuard/IPsec for mTLS
- Test connectivity between services
- Test NetworkPolicies
- Compare with Linkerd behavior

### 2. Evaluate Feature Loss
- Document lost L7 features
- Determine if acceptable
- Find alternatives where critical
- Get validation

### 3. Plan Migration
- Create detailed migration plan
- Identify all linkerd.io/inject annotations
- Plan for removing ServiceProfiles if any
- Prepare rollback plan

### 4. Remove Linkerd
- If PoC successful:
  - Remove infrastructure/linkerd-crds/
  - Remove infrastructure/linkerd/
  - Remove argocd/linkerd-*.yaml
  - Remove from apps-*.yaml
  - Remove linkerd.io/inject annotations from service template and elsewhere
  - Update sync-waves
  - Update docs

### 5. Configure CNI mTLS
- Enable encryption in CNI
- Configure NetworkPolicies as needed
- Validate security posture

### 6. Validate Observability
- Ensure metrics/logs/traces still work
- Kube-Prometheus/Loki/Tempo must function without Linkerd golden signals

## Constraints
- MUST do PoC first and validate
- Have rollback plan ready
- Test in Floci thoroughly before other environments
- This is high risk

## Deliverables
- PoC results documented
- CNI with mTLS deployed
- Linkerd completely removed
- All annotations removed
- Observability validated
- Rollback plan tested
