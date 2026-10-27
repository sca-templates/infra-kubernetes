# ADR-005: Replace Kafka/Strimzi with NATS JetStream (Togglable)

## Status

Proposed

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

- Deploy NATS JetStream with toggle in values
- Remove Strimzi operator and Kafka CRs
- Document toggle procedure
