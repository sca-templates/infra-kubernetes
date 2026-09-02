# Project: Implement Kafka

Area: Data · Wave 40 · Environments: local→dev→qa→prod
Depends on: strimzi (#6) — operator must be present.
Project done when: `Kafka`/`KafkaNodePool` CRs present; broker pods `Running`;
SCRAM auth works; topic can be produced/consumed.

## Milestone M1 — Kafka cluster + SCRAM

M1 done when: brokers stable + SCRAM-auth produce/consume works.

- [ ] Issue #11 · `Kafka`/`KafkaNodePool` CRs + SCRAM auth
  Depends on: strimzi (#6)
  - [ ] `infrastructure/kafka/` CRs for 4 envs
        - [ ] local/dev: 1 broker; qa/prod: 3 brokers + TLS/SCRAM
        - Commits: `feat(kafka): kafka cluster and node pool CRs`
  - [ ] SCRAM-SHA-512 users + listeners
        Commits: `feat(kafka): scram auth and listeners`
  - [ ] smoke: topic create/produce/consume over SCRAM
        Commits: `test(kafka): scram produce/consume smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(kafka): mark deployed`
  Issue done when: brokers `Running` + SCRAM produce/consume works.

No natural further phases → issues stay under M1.
