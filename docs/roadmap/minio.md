# Project: MinIO (retired)

Area: Delivery & Resilience · Wave 70 · Status: **retired**.

MinIO was evaluated as the local S3 backend for Velero and removed from PR
109: the upstream `quay.io/minio/minio` image is no longer publicly pullable,
and Floci already provides an S3 emulator in every local/EKS smoke run. Velero
now points at `http://floci.cloud.svc.cluster.local:4566` and the
`floci-buckets` Job creates its bucket.

- [x] Issue #22 · Evaluate `minio/minio` (local)
  - [x] chart, overlays, credentials and bucket-creation Job
  - [x] smoke: AWS CLI round-trip
  - [x] decision: retire MinIO in favour of Floci S3 (no in-cluster object
        store); see [velero.md](velero.md)
