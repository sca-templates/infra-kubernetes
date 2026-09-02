# Kubernetes Basics Used in This Repo

The Kubernetes concepts this platform exercises, kept general and stable.
This page is **not** a substitute for the official material — it points at it.
Readers entirely new to Kubernetes should pair this with the linked official
docs before diving into [architecture.md](architecture.md).

## Objects and the API

- **Namespaces** — logical partitions of the cluster; this repo's scheme is in
  [architecture.md](architecture.md).
- **Deployment / StatefulSet / DaemonSet** — workload controllers; the catalog
  uses the upstream charts' defaults scaled per env profile.
- **Services** — stable network endpoints in front of pods; the template's
  `templates/service.yaml` exposes one per service.
- **ConfigMaps and Secrets** — configuration vs sensitive data. Secrets are
  projected by ESO ([secrets.md](secrets.md)).

Official: [Overview of Kubernetes Objects](https://kubernetes.io/docs/concepts/overview/working-with-objects/).

## Controllers and operators

- **Reconciliation loop** = control loop. A controller watches a desired state
  and converges the cluster toward it. This is the engine behind *everything
  in this repo*.
- **Operator** = controller + custom resource definitions (CRDs). Examples in
  the catalog: CloudNativePG (`Cluster`), Strimzi (`Kafka`/`KafkaNodePool`),
  redis-operator (`Redis`), cert-manager (`Certificate`), ESO
  (`ExternalSecret`). CRDs arrive at wave -10 (operators) before CRs at wave 40
  ([architecture.md](architecture.md#sync-wave-map)).

Official: [Kubernetes Operators](https://kubernetes.io/docs/concepts/extend-kubernetes/extend-cluster/),
[CNCF Operators 101](https://www.cncf.io/blog/2020/10/02/kubernetes-operators-101/).

## Helm

- **Chart** = packaged Kubernetes app (templates + values). This repo pins
  official upstream charts by version and passes values from
  `infrastructure/` + `envs/`
  ([architecture.md](architecture.md), [onboarding-new-service.md](onboarding-new-service.md)).
- **Values** = chart inputs; shared defaults vs per-env overlays.
- `values.schema.json` in `charts/service-template/` validates values.

Official: [Helm Charts](https://helm.sh/docs/topics/charts/).

## GitOps and ArgoCD

- **GitOps** = git is the single source of truth; the cluster converges to it
  ([workflow.md](workflow.md)).
- **Application / ApplicationSet** — ArgoCD's units; this repo uses an
  app-of-apps pattern: root `Application` → `ApplicationSet` → per-component
  app ([architecture.md](architecture.md)).
- **Sync-wave** — ordering annotation so dependencies apply in order.

Official: [ArgoCD Concepts](https://argo-cd.readthedocs.io/en/stable/core_concepts/).

## Networking

- **Ingress / Gateway** — L7 entry; this platform routes through Kong (Phase 8)
  instead of a stock ingress controller.
- **Service mesh (Linkerd)** — mTLS between pods + golden signals (Phases 4/9).
- **ServiceMonitors** — Prometheus operators' scrape config (Phase 14).

Official: [Kubernetes Network Concepts](https://kubernetes.io/docs/concepts/services-networking/service/),
[ServiceMonitor spec](https://prometheus-operator.dev/docs/api-reference/api/).

## Storage and state

- **PV / PVC / StorageClass** — persistent volumes and the classes that back
  them; `prod` uses real storage classes ([architecture.md](architecture.md)).
- **CNPG** — PostgreSQL operator managing `Cluster` CRs (Phase 5/10).
- **Velero** — cluster backup/restore to object storage (Phase 18).

Official: [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/).

## Identity and security

- **ServiceAccounts** — pod identity, used by Vault k8s auth
  ([secrets.md](secrets.md)).
- **RBAC** — who may do what against the API.
- **NetworkPolicy / mTLS** — pod-communication control (Linkerd).

Official: [Authenticating](https://kubernetes.io/docs/reference/access-authn-authz/authentication/).

## Working locally

The local substrate is a single-node `kind` cluster
(`make cluster-up`); the pinned CLI toolchain lives in `~/.local/bin`
(`make prereqs`). Everything reachable from a laptop via `make port-forward`. See
[../README.md](../README.md).
