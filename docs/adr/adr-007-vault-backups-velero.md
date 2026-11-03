# ADR-007: Vault Raft Snapshots and Velero Backups

## Status

Accepted (implementation landed; live restore validation pending)

## Context

Vault stores secrets as source of truth. CNPG databases need backups. Cluster state needs protection. RDS replacement and production readiness require comprehensive backup strategy.

## Decision

Implement a three-layer backup strategy:

1. **Velero** - Cluster-level backups including resources and PVs (prioritize Phase 18)
2. **Vault Raft snapshots** - Specific backup of Vault's Raft datastore to object storage via CronJob
3. **CNPG backups** - Native CNPG backups to object storage with PITR

## Consequences

- Multiple backup mechanisms (complementary, not redundant)
- More operational complexity
- Better DR capability
- Must test all restore procedures
- Velero is critical dependency before disruptive migrations

## Implementation

- Velero runs in all four environments: `local` on Floci S3, external buckets
  elsewhere; scheduled backups cover the critical namespaces.
- CNPG clusters write Barman base backups + WAL with daily `ScheduledBackup`s;
  the restore smoke proves PITR and latest-backup restores.
- A `vault-raft-snapshot` CronJob saves, inspects, uploads, and ages out Vault
  Raft snapshots; it is a dedicated Application at wave 90.
- Backup credentials are projected by ESO (`secret/cnpg/<env>`,
  `secret/vault-snapshot/<env>`, `secret/velero/credentials`).
- Runbooks and environment retention live in [backups.md](../backups.md).
- Live restore validation on the Floci EKS substrate is the remaining gate.
