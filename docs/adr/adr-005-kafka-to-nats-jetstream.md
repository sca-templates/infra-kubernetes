# ADR-005: Replace Kafka/Strimzi with NATS JetStream (Togglable)

## Status

Accepted (2026-11-15)

## Context

Kafka (via Strimzi) is deployed as event backbone but has no consumers currently. AWS SNS/SQS can be used initially with near-zero cost. For self-hosted option, NATS JetStream is lighter weight.

## Decision

Replace Kafka/Strimzi with NATS JetStream. NATS must be configurable/togglable to switch between:

1. SNS/SQS mode - external AWS managed services (outside K8s, not managed by this repo)
2. NATS JetStream mode - in-cluster self-hosted

## Consequences

- Simpler operations if using SNS/SQS
- NATS is lighter weight than Kafka
- Need toggle mechanism in GitOps configuration
- Must remove all Kafka/Strimzi components
- No consumers currently so migration is cleaner
- NATS deployed in "ready but idle" state initially

## Implementation

- Deploy NATS JetStream and NACK: NATS at wave 40 (server, JetStream, file
  store) and NACK at wave 50 (controller + CRDs). The tier ships **idle** — no
  `Stream`/`Consumer` CRs. Landed in C1.
- Toggle SNS/SQS vs NATS per environment with optional application descriptors.
  `argocd/messaging-<env>.yaml` is a dedicated `ApplicationSet` whose git files
  generator reads `argocd/messaging/<env>/*.yaml`. The `nats.yaml` and
  `nack.yaml` descriptors are present in NATS mode and absent in SNS/SQS mode:
  removing them removes the generated Applications (and their resources), so
  SNS/SQS deploys nothing in the cluster. The per-env values overlays
  (`envs/<env>/{nats,nack}.yaml`) stay in git for either mode.
- Project the messaging contract through Vault/ESO. Every environment exposes
  `secret/messaging/<env>` in KV-v2 with:
  - `mode`: `nats` or `sns-sqs`;
  - `nats_url`: in-cluster NATS endpoint when `mode=nats`;
  - `sns_topic_arn`, `sqs_queue_url`, `aws_region` (and, where applicable,
    `aws_endpoint_url` / AWS credentials): external coordinates when
    `mode=sns-sqs`, provisioned out of band.
  Consumers own their `ExternalSecret`/workload wiring and switch backends from
  `mode` without code changes. `bootstrap/seed-vault.sh` seeds the local
  `mode=nats` contract; dev/qa/prod provision their paths out of band.
- Consumers declare their `Stream`/`Consumer` CRs only in NATS mode. The
  ApplicationSet ordering keeps NACK (wave 50) after the NATS server (wave 40);
  a consumer that owns streams must sit at a later wave.
- Remove Strimzi, Kafka CRs, Kafka values and the Kafka-specific wiring.
- Document the toggle procedure and the stream/consumer migration (C4).
