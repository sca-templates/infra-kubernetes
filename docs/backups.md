# Backup and Restore

The platform uses three **complementary** backup layers. They protect different
things and are not interchangeable:

| Layer | Protects | Mechanism | Source of truth |
| --- | --- | --- | --- |
| Velero | Kubernetes API objects (and PVs where a CSI driver exists) | Scheduled `Backup` to object storage | `infrastructure/velero/`, `envs/<env>/velero.yaml`, `argocd/apps-<env>.yaml` |
| CloudNativePG | `postgres-app` and `keycloak-db` data | Barman base backups + WAL archiving; PITR | `infrastructure/postgres-app/manifests/` |
| Vault | The Raft datastore (secrets SSOT) | `vault operator raft snapshot` CronJob to object storage | `infrastructure/vault/manifests/`, `infrastructure/vault/backup/manifests/` |

The datastore-native layers are the authoritative restore path for their data.
Velero restores the surrounding Kubernetes objects; it does not replace a CNPG
PITR or a Vault Raft restore.

## Environment gradient

| Environment | Object store | Velero bucket | CNPG bucket | Vault bucket | Retention |
| --- | --- | --- | --- | --- | --- |
| `local` | Floci S3 (`http://floci.cloud.svc.cluster.local:4566`) | `velero` | `cnpg-backups` | `vault-snapshots` | Velero 7d · CNPG 7d · Vault 7d |
| `dev` | external S3 | `sca-dev-velero` | `sca-dev-cnpg` | `sca-dev-vault-snapshots` | 30d · 30d · 30d |
| `qa` | external S3 | `sca-qa-velero` | `sca-qa-cnpg` | `sca-qa-vault-snapshots` | 30d · 30d · 30d |
| `prod` | external S3 | `sca-prod-velero` | `sca-prod-cnpg` | `sca-prod-vault-snapshots` | 90d · 90d · 90d |

`local` uses Floci's fixed dummy credentials (`test`/`test`). The local buckets
are created by the `floci-buckets` Job in
`infrastructure/velero/manifests/floci-buckets-job.yaml`. On an external-S3
environment the Job probes the Floci endpoint, finds it unreachable, and exits
successfully without changing anything.

External buckets must exist before the first scheduled backup. Create them out
of band and grant the credentials write, list, and delete permissions on their
prefixes.

## Credentials

All object-store credentials live in Vault and are projected by ESO; no
credential is stored in git.

| Vault path | Projected Secret | Consumer |
| --- | --- | --- |
| `secret/velero/credentials` | `velero-credentials` | Velero |
| `secret/cnpg/<env>` | `cnpg-backup-credentials` | both CNPG `Cluster`s |
| `secret/vault-snapshot/<env>` | `vault-snapshot-credentials` | Vault snapshot CronJob |

`bootstrap/seed-vault.sh` seeds the `local` dummy values. On `dev`/`qa`/`prod`,
write the paths with the environment's real credentials before expecting the
backup jobs to run. See [secrets.md](secrets.md).

## Schedules

| Job | Resource | Schedule |
| --- | --- | --- |
| Velero critical namespaces | `Schedule/velero-critical-namespaces` | `0 2 * * *` |
| `postgres-app` base backup | `ScheduledBackup/postgres-app-daily` | `0 30 1 * * *` (six-field CNPG cron) |
| `keycloak-db` base backup | `ScheduledBackup/keycloak-db-daily` | `0 45 1 * * *` (six-field CNPG cron) |
| Vault Raft snapshot | `CronJob/vault-raft-snapshot` | `30 1 * * *` |

Cron expressions are evaluated by the Kubernetes controller in its timezone
(UTC on this platform). CNPG uses a six-field expression with seconds first.

## Check backup health

```bash
kubectl -n velero get backupstoragelocation,schedule,backup
kubectl -n data get cluster,backup,scheduledbackup
kubectl -n vault get cronjob,job
kubectl -n vault get externalsecret vault-snapshot-credentials
```

A CNPG `Cluster` is archiving when its `ContinuousArchiving` condition is
`True`:

```bash
kubectl -n data get cluster postgres-app \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
```

## Velero: backup and restore

Velero's schedule covers `data`, `vault`, `keycloak`, `kong`, and
`cert-manager`. In `local` it backs up Kubernetes objects only
(`snapshotVolumes: false`); on a CSI-capable cluster the environment overlay
enables volume snapshots.

Create an ad-hoc backup:

```bash
name="manual-$(date +%Y%m%d%H%M%S)"
kubectl -n velero create -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: ${name}
  namespace: velero
spec:
  includedNamespaces:
    - data
    - vault
  ttl: 24h0m0s
EOF
kubectl -n velero wait --for=jsonpath='{.status.phase}'=Completed \
  "backup/${name}" --timeout=15m
```

Restore a backup. The example restores a namespace that was deleted; adjust
the namespace list and review `existingResourcePolicy` before restoring over a
live environment:

```bash
backup="manual-20261031T120000Z"
restore="restore-$(date +%Y%m%d%H%M%S)"
kubectl -n velero create -f - <<EOF
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: ${restore}
  namespace: velero
spec:
  backupName: ${backup}
  includedNamespaces:
    - data
EOF
kubectl -n velero wait --for=jsonpath='{.status.phase}'=Completed \
  "restore/${restore}" --timeout=15m
kubectl -n velero describe "restore/${restore}"
```

Verify the expected objects and PVCs. If the Velero CLI is installed,
`velero backup get`, `velero restore get`, and `velero restore logs` are
equivalent read paths. Restore datastore contents with CNPG/Vault, not by
copying a Velero volume snapshot into a live cluster.

## CloudNativePG: backup and PITR

Both clusters archive WAL and take scheduled base backups. CNPG recovery
**always bootstraps a new `Cluster`**; it never restores in place over the
source.

List available backups:

```bash
kubectl -n data get backup \
  -o custom-columns='NAME:.metadata.name,CLUSTER:.spec.cluster.name,PHASE:.status.phase,BACKUPID:.status.backupId'
```

### Restore from a `Backup` object

Use this when the wanted base backup is present in the `data` namespace. Set
`database` and `owner` to match the source (`app`/`app` for `postgres-app`,
`keycloak`/`keycloak` for `keycloak-db`).

```bash
kubectl -n data apply -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-app-restore
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:18.4-standard-trixie
  storage:
    size: 10Gi
  bootstrap:
    recovery:
      backup:
        name: postgres-app-daily-20261031
      secret:
        name: postgres-app-credentials
      database: app
      owner: app
EOF
kubectl -n data wait --for=condition=Ready cluster/postgres-app-restore \
  --timeout=15m
```

### Point-in-time restore

For PITR, point the recovery at the object store and set `targetTime` (RFC3339).
This works even when the `Backup` object is gone but the base backup and WAL
archive remain. `source` must match the folder name in the destination path
(`s3://<bucket>/<cluster-name>`).

```bash
kubectl -n data apply -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-app-pitr
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:18.4-standard-trixie
  storage:
    size: 10Gi
  bootstrap:
    recovery:
      source: postgres-app
      secret:
        name: postgres-app-credentials
      database: app
      owner: app
      recoveryTarget:
        targetTime: "2026-10-31T12:00:00Z"
  externalClusters:
    - name: postgres-app
      barmanObjectStore:
        destinationPath: s3://sca-prod-cnpg/postgres-app
        s3Credentials:
          accessKeyId:
            name: cnpg-backup-credentials
            key: ACCESS_KEY_ID
          secretAccessKey:
            name: cnpg-backup-credentials
            key: ACCESS_SECRET_KEY
          region:
            name: cnpg-backup-credentials
            key: AWS_REGION
EOF
```

For `local`, add the Floci `endpointURL` and use the `cnpg-backups` bucket.
For `keycloak-db`, use `source: keycloak-db`, its bucket path, and
`database: keycloak`/`owner: keycloak`.

After the restore cluster is `Ready`, connect to its primary and verify the
expected rows before switching consumers:

```bash
kubectl -n data get cluster postgres-app-pitr -o wide
kubectl -n data get pods -l cnpg.io/cluster=postgres-app-pitr
```

Remove the restore cluster and its PVCs when validation is complete. Never
delete the source cluster or its object-store prefix as part of a test.

`bootstrap/smoke-postgres-app.sh` automates both paths: a PITR round-trip on
`postgres-app` and a latest-backup restore on `keycloak-db`. Set
`SMOKE_CNPG_PITR=0` to skip the PITR half.

## Vault: Raft snapshot and restore

The CronJob authenticates with the `vault-snapshot` Kubernetes-auth role, saves
a Raft snapshot to a shared `emptyDir`, validates it with
`vault operator raft snapshot inspect`, uploads it to
`s3://<bucket>/raft/vault-<timestamp>.snap`, and deletes objects older than the
environment retention.

Trigger a snapshot outside the schedule:

```bash
job="vault-raft-snapshot-manual-$(date +%Y%m%d%H%M%S)"
kubectl -n vault create job --from=cronjob/vault-raft-snapshot "${job}"
kubectl -n vault wait --for=condition=complete "job/${job}" --timeout=15m
kubectl -n vault logs "job/${job}" -c snapshot
kubectl -n vault logs "job/${job}" -c upload
```

Look for `VAULT_SNAPSHOT_OK` (snapshot saved and inspected) and
`VAULT_SNAPSHOT_UPLOADED` (object confirmed with `head-object`). List snapshots
with your S3 tooling; in `local`, run an AWS CLI pod against the Floci service
with the dummy `test`/`test` pair.

### Restore

A Raft restore overwrites the cluster's data and is a full-cluster operation.
Use a maintenance window, take a fresh snapshot first, and verify the target
bucket/object before copying it into a pod.

1. Confirm the target Vault pod is initialized, unsealed, and `active`.
2. Download the chosen snapshot and copy it to the active pod:
   `kubectl cp ./vault-<timestamp>.snap vault/vault-0:/tmp/vault.snap`.
3. Run the restore with a privileged token:
   `kubectl -n vault exec -it vault-0 -- env VAULT_ADDR=... VAULT_CACERT=... vault operator raft snapshot restore -force /tmp/vault.snap`.
4. Wait for the server logs to report `post-unseal setup complete` and
   `vault is unsealed`; the command returns before the background restore
   finishes.
5. Unseal with the **original** unseal keys if the pod reports sealed.
6. Verify `vault status` (`sealed=false`), that the Raft applied index advanced,
   and that a known KV path (for example `secret/postgres-app/<env>`) is
   readable through ESO or the CLI.

On a healthy HA cluster the active node distributes the snapshot to the
followers. If the cluster is being rebuilt, bring one node up, restore, then
scale the StatefulSet back up and confirm the peers rejoin with
`vault operator members`. Full details are in the upstream
[HashiCorp restore procedure](https://developer.hashicorp.com/vault/docs/sysadmin/snapshots/restore).

`bootstrap/smoke-vault.sh` triggers a real snapshot Job and asserts both log
markers. Set `SMOKE_KEEP_VAULT_JOB=1` to keep the Job for inspection.

## Troubleshooting

| Symptom | Likely cause | Check |
| --- | --- | --- |
| Velero `BackupStorageLocation` unavailable | Wrong bucket/credentials/endpoint | `kubectl -n velero describe backupstoragelocation default`; confirm the bucket exists |
| Velero `Backup` `PartiallyFailed` | A resource could not be backed up | `kubectl -n velero describe backup <name>`; inspect `status.errors` |
| CNPG `ContinuousArchiving=False` | Missing bucket/credentials or unreachable endpoint | `kubectl -n data describe cluster <name>`; check the CNPG pod logs |
| CNPG `Backup` `failed` | Barman or object-store error | `kubectl -n data describe backup <name>`; check `status.error` |
| Vault Job `Init:Error` | `vault-snapshot` role/policy missing or TLS CA mismatch | re-run `bootstrap/seed-vault.sh`; check the init-container logs |
| Vault upload fails | S3 credentials/bucket/endpoint wrong | check the `upload` container logs and `vault-snapshot-credentials` |
| ExternalSecret not ready | Vault path missing or role wrong | `kubectl -n <ns> describe externalsecret <name>`; see [secrets.md](secrets.md) |

## Validation status

The manifests and smoke scripts are in git. A full live restore validation on
the Floci emulated EKS substrate is still required before these procedures are
treated as production-proven; `docs/status.md` records the current state.
