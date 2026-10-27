# Phase C: Kafka/Strimzi → NATS JetStream (Togglable)

## Objective
Replace Kafka with NATS JetStream. NATS must be configurable to toggle between SNS/SQS (external AWS, outside K8s) and NATS (in-cluster). Kafka/Strimzi completely removed.

## Context
From Phase A. No consumers currently use Kafka.

## Tasks

### 1. Research & Design NATS
- Evaluate NATS JetStream deployment (Helm chart, operator)
- Design toggle mechanism (values-based, feature flag)
- Plan CRDs/streams/consumers structure
- Define sync-waves

### 2. Add NATS to Catalog
- Add NATS JetStream to infrastructure/
- Add to apps-<env>.yaml (or dedicated apps)
- Configure per environment
- Make it togglable via values

### 3. Implement Toggle
- Design configuration to switch between:
  - SNS/SQS mode (external, managed by AWS) - not deployed in K8s
  - NATS mode (in-cluster JetStream)
- Ensure services can switch without code changes
- Document the toggle procedure

### 4. Remove Kafka/Strimzi
- Remove infrastructure/strimzi/
- Remove infrastructure/kafka/
- Remove argocd/kafka-*.yaml
- Remove from apps-*.yaml
- Update all docs/references
- Update smoke tests

### 5. Deploy NATS in "ready but idle" state
- Deploy NATS JetStream operational
- No streams/consumers active by default
- Document how to enable when migrating from SNS/SQS

## Constraints
- Toggle must be clean (declarative GitOps)
- Follow sync-waves
- Update all references
- No consumers exist now so migration should be clean

## Deliverables
- NATS JetStream deployed and togglable
- Kafka/Strimzi completely removed
- Toggle mechanism documented and tested
- Docs updated
