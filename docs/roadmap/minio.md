# Project: Implement MinIO

Area: Delivery & Resilience · Wave 70 · Environments: local only (S3 stand-in for
Velero); not on dev/qa/prod.
Depends on: — (local-only object storage).
Project done when: MinIO `Running`; buckets for Velero exist; S3 access works
for the Velero backup backend (#23).

No natural phases → issues directly under the project.

- [x] Issue #22 · Deploy `minio/minio` (local)
  Depends on: —
  - [x] `infrastructure/minio/` values + local-only overlays
        - Commits: `feat(minio): minio chart and local overlays`
  - [x] bucket(s) for Velero + `secret/minio/root` projected by ESO
        The chart's `post-install` hook is replaced by the normal
        `minio-buckets` Job (`velero`, `vault-snapshots`, `cnpg-backups`).
        Commits: `feat(minio): velero bucket and credentials`
  - [x] smoke: in-cluster AWS CLI Job lists/head-buckets and round-trips an object
        Commits: `test(minio): velero bucket smoke`
  - [x] docs: Work Log row + catalog Status → deployed
        Commits: `docs(minio): mark deployed`
  Issue done when: MinIO serves the Velero bucket; ready for Velero (#23).
