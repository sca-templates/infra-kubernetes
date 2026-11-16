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

- Deploy NATS JetStream and NACK as `ApplicationSet` elements: NATS at wave 40
  (server, JetStream, file store) and NACK at wave 50 (controller + CRDs). The
  tier ships **idle** — no `Stream`/`Consumer` CRs. Landed in C1.
- Make the SNS/SQS vs NATS choice declarative per environment (toggle) and
  project the messaging contract (`mode` + endpoints) through Vault/ESO. The
  consumers declare their `Stream`/`Consumer` CRs once the mode is NATS.
- Remove Strimzi, Kafka CRs, Kafka values and the Kafka-specific wiring.
- Document the toggle procedure and the stream/consumer migration.
