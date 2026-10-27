# Phase B: Velero, CNPG Backups, Vault Raft Snapshots (Priority)

## Objective
Prioritize resilience - implement Velero, configure CNPG backups/PITR, and set up Vault Raft snapshots to S3/MinIO. Validate restores before doing disruptive migrations.

## Context
From Phase A planning. This is CRITICAL - must have proven backups before replacing RDS or doing Linkerd/Keycloak migrations.

## Tasks

### 1. MinIO/S3 Backend
- Complete/validate MinIO for local (Phase 17)
- Define buckets/credentials for dev/qa/prod to S3
- Configure proper IAM/policies

### 2. Deploy Velero (Phase 18)
- Install Velero with AWS S3 plugin
- Configure CSI snapshots if applicable
- Set up schedules for critical namespaces (data, vault, keycloak if still present, etc.)
- Test backup/restore workflow

### 3. CNPG Backups & PITR
- Configure CNPG backup to object store (barman/cloudnative-pg backup)
- Set retention policies
- Test full backup and Point-in-Time Recovery in Floci/local
- Document restore procedures
- Validate this covers RDS replacement needs

### 4. Vault Raft Snapshots
- Create CronJob to take Raft snapshots
- Upload to S3/MinIO with rotation
- Create restore procedure/runbook
- Test snapshot and restore in Floci
- This is COMPLEMENTARY to Velero (different backup type)

### 5. Validation & Smoke Tests
- Add smoke tests for backup functionality
- Document all procedures in docs/
- Update status/roadmap

## Constraints
- Must test restores, not just backups
- Follow GitOps patterns (ArgoCD apps)
- Respect sync-waves
- No floating tags
- Document everything

## Deliverables
- Velero deployed and configured
- CNPG backups working with tested restore
- Vault Raft snapshots working with tested restore
- Runbooks documented
- Smoke tests passing
