# ADR-003: ArgoCD Sync Policies

## Status

Accepted

## Context

Different environments have different risk profiles and operational requirements. A one-size-fits-all sync policy is not appropriate.

## Decision

- **local**: auto-sync + prune enabled for rapid iteration
- **dev**: auto-sync + prune enabled for platform, services synced on demand via promote workflow
- **qa**: auto-sync enabled, prune disabled for safety
- **prod**: manual sync only, no auto-sync or prune

## Consequences

- qa/prod have extra protection against accidental deletions
- local/dev allow faster iteration
- prod requires explicit approval for all changes
- Services follow app-repo-as-source pattern with promotion gates
