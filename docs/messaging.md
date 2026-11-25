# Messaging: Toggle and Stream Ownership

State and runbook for the ADR-005 event backbone. The platform owns the idle NATS/NACK tier and the Vault contract; each service owns its `Stream`/`Consumer` topology. This is the detail page for the toggle described in [ADR-005](adr/adr-005-kafka-to-nats-jetstream.md); current deployment facts stay in [status.md](status.md) and the wiring rationale in [architecture.md](architecture.md#deviations-log).

## Contract

Every environment exposes `secret/messaging/<env>` in Vault KV-v2. Services project that path with their own `ExternalSecret` and select the backend from `mode`; the platform never copies the contract into service namespaces. `bootstrap/seed-vault.sh` seeds only `local` with `mode=nats`; dev/qa/prod provision the path out of band. See [secrets.md](secrets.md#kv-path-inventory) for the path inventory.

| Key | Used by | Meaning |
| --- | --- | --- |
| `mode` | both | `nats` or `sns-sqs`; selects the backend without a code change |
| `nats_url` | `nats` | in-cluster endpoint; local seed is `nats://nats.data.svc.cluster.local:4222` |
| `sns_topic_arn`, `sqs_queue_url`, `aws_region` | `sns-sqs` | external coordinates provisioned outside this repository |
| `aws_endpoint_url`, credential keys | `sns-sqs` (optional) | emulator endpoint and service-specific credentials; never stored in git |

## Mode matrix

| Mode | Descriptors under `argocd/messaging/<env>/` | Generated Applications | In-cluster state |
| --- | --- | --- | --- |
| `nats` | `nats.yaml` and `nack.yaml` present | `nats-<env>` (wave 40) and `nack-<env>` (wave 50) | NATS server Ready with JetStream enabled and zero streams; NACK CRDs `Established`, controller Ready, cluster-wide watch |
| `sns-sqs` | both files absent | none | no NATS/NACK Applications or workloads; the external backend is out of band |

The per-env overlays `envs/<env>/{nats,nack}.yaml` stay in git in both modes, so restoring NATS is a descriptor-only change. Never leave only one descriptor: NACK connects to NATS at startup and has no purpose without the server. The `resources-finalizer.argocd.argoproj.io` finalizer on the generated Applications prunes their resources when descriptors are removed.

## Toggle procedure

1. Choose the target mode per environment. `local` and `dev` auto-sync with prune, `qa` auto-syncs without prune, and `prod` is manual; the generated Applications follow the same profile. On deletion, the Application finalizer still prunes the managed resources, so verify the result instead of assuming it from the sync policy.
2. Open a reviewed PR changing **both** descriptors under `argocd/messaging/<env>/`: add them to enable NATS, remove them to select SNS/SQS. Keep the chart pins and values overlays unchanged; the file set in git is the deployment gate.
3. Provision the matching `secret/messaging/<env>` before the workloads change. For `local`, rerun the seed; for the other environments, update the Vault path out of band. Set `mode` plus the endpoint keys for the target mode and rotate credentials that are no longer used. No values or credentials belong in this repository.
4. Merge and let ArgoCD reconcile. Generated Applications are automated in `local`/`dev` (prune), automated in `qa` (no prune) and manual in `prod`. Check them with `kubectl -n argocd get applicationset messaging-<env>` and `kubectl -n argocd get application nats-<env> nack-<env>`: both names must exist in NATS mode and return `NotFound` in SNS/SQS mode.
5. Verify the cluster state. In NATS mode, `make smoke COMPONENT=nats` must report JetStream enabled with zero streams and `make smoke COMPONENT=nack` must report the controller Ready, the six `jetstream.nats.io` CRDs `Established` and a cluster-wide watch. In SNS/SQS mode, `kubectl -n data get statefulset nats` and `kubectl -n nats get deployment nack` must return `NotFound`; both standalone smokes report `[SKIP]` when their Application is absent, matching the smoke CI gate.
6. Switch consumers in their own repositories. Services read the same `mode` from the projected Secret; no service image change is required for the transport selection. Any stale CRs or workload wiring must be removed in the service PR, not by hand in the cluster.

If a step fails, stop and roll back the descriptor PR rather than patching the cluster forward. Follow the escalation gate in [workflow.md](workflow.md#the-escalation-gate).

## Service-owned streams and consumers

No `Stream` or `Consumer` CR ships in this repository: the tier stays ready-but-idle until a consumer declares its own topology. NACK watches all namespaces, so a service declares its CRs in `deploy/` in its own repository and places them at a wave later than 50. The CRDs belong to the `jetstream.nats.io` group and are installed by NACK.

Before the first CR, the service must project `secret/messaging/<env>`, use `nats_url` only when `mode=nats`, and verify that NACK is Ready. The current tier is idle and **unauthenticated**; the first consumer must add NATS accounts/credentials through Vault/ESO and extend the contract before any non-cluster use. That work is a consumer-driven follow-up, not part of the idle platform.

To move a service from SNS/SQS to NATS: flip the environment to NATS mode, confirm the platform smokes, then add the service's `Stream`/`Consumer` CRs and verify them with `kubectl -n <service-ns> get streams.jetstream.nats.io,consumers.jetstream.nats.io`. The CRs must exist only in NATS mode.

To move a service from NATS to SNS/SQS: remove the service's `Stream`/`Consumer` CRs in its own repo first, then remove the platform descriptors and update the Vault contract. Leftover CRs will not be reconciled once NACK is gone.

## Consumer validation

```text
kubectl -n <service-ns> get externalsecret <service-messaging>
kubectl -n <service-ns> get secret <service-messaging>
kubectl -n <service-ns> get streams.jetstream.nats.io,consumers.jetstream.nats.io
```

The `ExternalSecret` must be `SecretSynced`, the projected Secret must contain `mode` and the keys for that mode, and the CR list must show the service's CRs in NATS mode and be empty in SNS/SQS mode. On `SecretSyncedError`, check the Vault path and the k8s-auth role as described in [workflow.md](workflow.md#troubleshooting-quick-refs); on stale CRs, remove them from the service repository.

## Historical references

Kafka and Strimzi strings remain only as migration history in [CHANGELOG.md](../CHANGELOG.md), [ADR-005](adr/adr-005-kafka-to-nats-jetstream.md), [roadmap.md](roadmap.md) and [migration-inventory-phase-a.md](migration-inventory-phase-a.md). No runtime file, values overlay or ArgoCD descriptor references them.
