# Backup and Restore

The platform uses three **complementary** backup layers. They protect different
things and are not interchangeable:

| Layer | Protects | Mechanism | Source of truth |
| --- | --- | --- | --- |
| Velero | Kubernetes API objects (and PVs where a CSI driver exists) | Scheduled `Backup` to object storage | `infrastructure/velero/`, `envs/<env>/velero.yaml`, `argocd/apps-<env>.yaml` |
| CloudNativePG | `postgres-app` and `zitadel-db` data | Barman Cloud plugin base backups + WAL archiving; PITR | `infrastructure/postgres-app/manifests/` |
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

CNPG 1.30 archives WAL and takes base backups through
`barman-cloud.cloudnative-pg.io`. Each `Cluster` references one `ObjectStore`
per environment; the `ObjectStore` carries the destination path, credentials,
compression settings and retention policy that used to live under
`spec.backup.barmanObjectStore`. The local `ObjectStore`s set
`AWS_REQUEST_CHECKSUM_CALCULATION` and `AWS_RESPONSE_CHECKSUM_VALIDATION` to
`when_required` in `instanceSidecarConfiguration.env` for Floci's S3 emulation;
the external-S3 environments keep the boto3 default checksum behaviour. All
`Cluster`s use `18.4-standard-trixie`: the plugin sidecar supplies the Barman
Cloud binaries and `standard` also carries `pgaudit` and `pgvector`, so the
deprecated `system` flavor is gone before the CNPG 1.32 operator upgrade.

External buckets must exist before the first scheduled backup. Create them out
of band and grant the credentials write, list, and delete permissions on their
prefixes.

## Credentials

All object-store credentials live in Vault and are projected by ESO; no
credential is stored in git.

| Vault path | Projected Secret | Consumer |
| --- | --- | --- |
| `secret/velero/credentials` | `velero-credentials` | Velero |
| `secret/cnpg/<env>` | `cnpg-backup-credentials` | both CNPG `ObjectStore`s |
| `secret/vault-snapshot/<env>` | `vault-snapshot-credentials` | Vault snapshot CronJob |

`bootstrap/seed-vault.sh` seeds the `local` dummy values. On `dev`/`qa`/`prod`,
write the paths with the environment's real credentials before expecting the
backup jobs to run. See [secrets.md](secrets.md).

## Schedules

| Job | Resource | Schedule |
| --- | --- | --- |
| Velero critical namespaces | `Schedule/velero-critical-namespaces` | `0 2 * * *` |
| `postgres-app` base backup | `ScheduledBackup/postgres-app-daily` | `0 30 1 * * *` (six-field CNPG cron) |
| `zitadel-db` base backup | `ScheduledBackup/zitadel-db-daily` | `0 15 2 * * *` (six-field CNPG cron) |
| Vault Raft snapshot | `CronJob/vault-raft-snapshot` | `30 1 * * *` |

Cron expressions are evaluated by the Kubernetes controller in its timezone
(UTC on this platform). CNPG uses a six-field expression with seconds first.

## Check backup health

```bash
kubectl -n velero get backupstoragelocation,schedule,backup
kubectl -n data get cluster,backup,scheduledbackup,objectstore
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

Velero's schedule covers `data`, `vault`, `zitadel`, `kong`, and
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

### Restore from the object store

CNPG selects the latest recoverable base backup from the referenced
`ObjectStore` and bootstraps a new `Cluster`. `serverName` is the source
`Cluster` name; `barmanObjectName` is the per-environment `ObjectStore` from
`infrastructure/postgres-app/manifests/objectstore-<service>-<env>.yaml`.
Set `database` and `owner` to match the source (`app`/`app` for `postgres-app`,
`zitadel`/`zitadel` for `zitadel-db`).

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
      source: barman-cloud
      secret:
        name: postgres-app-credentials
      database: app
      owner: app
  externalClusters:
    - name: barman-cloud
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: postgres-app-prod
          serverName: postgres-app
EOF
kubectl -n data wait --for=condition=Ready cluster/postgres-app-restore \
  --timeout=15m
```

### Point-in-time restore

For PITR, keep the same plugin reference and set `targetTime` (RFC3339). This
works even when the `Backup` object is gone but the base backup and WAL archive
remain in the object store.

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
      source: barman-cloud
      secret:
        name: postgres-app-credentials
      database: app
      owner: app
      recoveryTarget:
        targetTime: "2026-10-31T12:00:00Z"
  externalClusters:
    - name: barman-cloud
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: postgres-app-prod
          serverName: postgres-app
EOF
```

For `local`, use `barmanObjectName: postgres-app-local`; the Floci `endpointURL`
and checksum settings already live in the `ObjectStore`. For `zitadel-db`, use
`zitadel-db-<env>` and `database: zitadel`/`owner: zitadel`.

After the restore cluster is `Ready`, connect to its primary and verify the
expected rows before switching consumers:

```bash
kubectl -n data get cluster postgres-app-pitr -o wide
kubectl -n data get pods -l cnpg.io/cluster=postgres-app-pitr
```

Remove the restore cluster and its PVCs when validation is complete. Never
delete the source cluster or its object-store prefix as part of a test.

`bootstrap/smoke-postgres-app.sh` automates both paths through the plugin: a
PITR round-trip on `postgres-app` and a latest-backup restore on `zitadel-db`.
It also asserts the `Cluster` plugin and the referenced `ObjectStore`. Set
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

1. Confirm the target Vault pod is initialized, unsealed, and `active`
   (`kubectl -n vault get pods -l vault-active=true`).
2. Download the chosen snapshot, copy it to the active pod, and compare the
   checksum on the host and in the pod before restoring:
   `kubectl cp ./vault-<timestamp>.snap vault/<active-pod>:/tmp/vault.snap`.
   Prefer `kubectl cp` over `kubectl exec -i … cat`; streamed copies can
   truncate large snapshots.
3. Run the restore with a privileged token:
   `kubectl -n vault exec -it <active-pod> -- env VAULT_ADDR=... VAULT_CACERT=... vault operator raft snapshot restore -force /tmp/vault.snap`.
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
| CNPG `ContinuousArchiving=False` | Missing `ObjectStore`, bucket/credentials, plugin sidecar or unreachable endpoint | `kubectl -n data describe cluster <name> objectstore <barmanObjectName>`; check the CNPG pod and plugin sidecar logs |
| CNPG `Backup` `failed` | Barman or object-store error | `kubectl -n data describe backup <name>`; check `status.error` |
| `NoSuchBucket` after a Floci restart | Local buckets were lost; the Velero `PreSync` Job already ran | re-sync `velero-local` so the `floci-buckets` Job recreates `velero`, `cnpg-backups` and `vault-snapshots` |
| Vault Job `Init:Error` | `vault-snapshot` role/policy missing or TLS CA mismatch | re-run `bootstrap/seed-vault.sh`; check the init-container logs |
| Vault upload fails | S3 credentials/bucket/endpoint wrong | check the `upload` container logs and `vault-snapshot-credentials` |
| ExternalSecret not ready | Vault path missing or role wrong | `kubectl -n <ns> describe externalsecret <name>`; see [secrets.md](secrets.md) |

## Validation status

Live restore validation passed on the Floci emulated EKS substrate on
2026-11-14:

| Layer | Command | Result |
| --- | --- | --- |
| Velero | `make smoke COMPONENT=velero` | `Backup` and `Restore` `Completed`; the deleted namespace and its marker were recovered |
| Velero schedule template | `Backup` from `Schedule/velero-critical-namespaces` | `Completed` (639 items, 0 errors) on 2026-11-14; backup `velero-critical-namespaces-manual-20261114154830` |
| CNPG | `make smoke COMPONENT=postgres-app` | PITR with A/B markers on `postgres-app`, latest-backup restore on `zitadel-db`; the 2026-11-14 historical run also restored `keycloak-db`, which E4 later removed. Re-run green on 2026-11-25 after the Barman Cloud plugin migration, with `ContinuousArchiving=True` on both clusters |
| Vault snapshot | `make smoke COMPONENT=vault` | `VAULT_SNAPSHOT_OK` + `VAULT_SNAPSHOT_UPLOADED` |
| Vault restore drill | manual, per the runbook above | Canary KV written, snapshot taken, canary deleted, Raft snapshot restored on the active node; the canary was recovered and ExternalSecrets stayed `SecretSynced` |

The schedule-created backup `velero-critical-namespaces-20261114195950` failed
only at the final S3 upload (`NoSuchBucket`) after the Floci restart; the bucket
was recreated and the same template re-ran to `Completed` (639 items). The
`Schedule` retains that failed reference as `status.lastBackup` until its next
real run.

`dev`/`qa`/`prod` still require their own external buckets and credentials
before the same procedures can be exercised there.
