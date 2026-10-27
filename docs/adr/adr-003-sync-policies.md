# ADR-003: Sync Policies

## Status
Accepted

## Context
Different environments have different risk profiles and need different sync behaviors.

## Decision
- **local**: auto-sync + prune (platform), no services
- **dev**: auto-sync + prune (platform), services synced on demand by promote workflow
- **qa**: auto-sync, NO prune (platform), services synced by promote workflow
- **prod**: manual sync (platform and services), services via version pin in services-prod.yaml

## Consequences
- qa/prod have extra protection against accidental pruning
- prod requires human intervention for all changes
- Clear promotion path
