# Barman Cloud plugin for CloudNativePG

CNPG-I plugin that adds S3-compatible base backup and WAL archiving to CloudNativePG `Cluster` resources through the `ObjectStore` CRD.

- Upstream chart: [cloudnative-pg/plugin-barman-cloud](https://cloudnative-pg.github.io/charts)
- Chart pin: `0.9.0` (`argocd/apps-<env>.yaml`)
- Image pins: `ghcr.io/cloudnative-pg/plugin-barman-cloud:v0.16.0` and `ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.16.0`
- Namespace: `cloudnative-pg`
- Wave: 10
- CRD: `objectstores.barmancloud.cnpg.io`
- No `Cluster` or `ObjectStore` resources live here; the backup configuration migrates from the datastores in `infrastructure/postgres-app/manifests/` in the following change.
