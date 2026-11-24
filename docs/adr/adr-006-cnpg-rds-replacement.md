# ADR-006: CloudNativePG as RDS Replacement

## Status

Proposed

## Context

Using managed RDS has ongoing costs. CloudNativePG is already deployed for `postgres-app` and `zitadel-db` (the former `keycloak-db` was removed in ADR-004 E4). With proper backups and HA, it can replace RDS.

## Decision

Use CloudNativePG as the primary PostgreSQL solution, replacing Amazon RDS. This requires:

- Validated automated backups to object storage (local: Floci S3)
- Point-in-Time Recovery (PITR) capability
- Velero for cluster/PV backups
- Proper HA configuration
- Tested restore procedures

## Consequences

- Cost savings on managed database
- More operational responsibility
- Must have robust backup strategy
- Need to validate in all environments
- DR procedures are critical

## Implementation

- Prioritize Velero (Phase 18).
- CNPG native backups (Barman base backups + WAL/PITR) landed in Phase B with
  a restore smoke; the live green run passed on 2026-11-14.
- Test restores thoroughly before treating the RDS replacement as proven.

The local phase ships Velero against Floci S3, plus the Phase B CNPG backup
path. See [backups.md](../backups.md).
