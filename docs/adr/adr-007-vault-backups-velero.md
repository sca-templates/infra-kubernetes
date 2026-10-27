# ADR-007: Vault Raft Snapshots and Velero Backups

## Status

Proposed

## Context

Vault stores secrets as source of truth. CNPG databases need backups. Cluster state needs protection. RDS replacement and production readiness require comprehensive backup strategy.

## Decision

Implement dual backup strategy:

1. **Velero** - Cluster-level backups including resources and PVs (prioritize Phase 18)
2. **Vault Raft snapshots** - Specific backup of Vault's Raft datastore to S3/MinIO via CronJob
3. **CNPG backups** - Native CNPG backups to object storage with PITR

## Consequences

- Multiple backup mechanisms (complementary, not redundant)
- More operational complexity
- Better DR capability
- Must test all restore procedures
- Velero is critical dependency before disruptive migrations

## Implementation

- Prioritize Velero deployment
- Create Vault snapshot CronJob
- Configure CNPG backups
- Document and test restore procedures
