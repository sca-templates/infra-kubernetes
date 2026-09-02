# Project: Implement MinIO

Area: Delivery & Resilience · Wave 70 · Environments: local only (S3 stand-in for
Velero); not on dev/qa/prod.
Depends on: — (local-only object storage).
Project done when: MinIO `Running`; buckets for Velero exist; S3 access works
for the Velero backup backend (#18).

No natural phases → issues directly under the project.

- [ ] Issue #17 · Deploy `minio/minio` (local)
  Depends on: —
  - [ ] `infrastructure/minio/` values + local-only overlays
        - Commits: `feat(minio): minio chart and local overlays`
  - [ ] bucket(s) for Velero + credentials in `.secrets/`
        Commits: `feat(minio): velero bucket and credentials`
  - [ ] smoke: `mc`/S3 client lists the Velero bucket
        Commits: `test(minio): velero bucket smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(minio): mark deployed`
  Issue done when: MinIO serves the Velero bucket; ready for Velero (#18).
