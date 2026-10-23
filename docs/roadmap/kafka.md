# Project: Implement Kafka

Area: Data · Wave 40 · Environments: local→dev→qa→prod
Depends on: strimzi (#11) — operator must be present.
Project done when: `Kafka`/`KafkaNodePool` CRs present; broker pods `Running`;
SCRAM auth works; topic can be produced/consumed.

## Milestone M1 — Kafka cluster + SCRAM

M1 done when: brokers stable + SCRAM-auth produce/consume works (1 broker
local/dev, 3 qa/prod; TLS + SCRAM-SHA-512 in every environment).

- [x] Issue #16 · `Kafka`/`KafkaNodePool` CRs + SCRAM auth
  Depends on: strimzi (#11)
  - [x] `infrastructure/kafka/` CRs for 4 envs
        - [x] local/dev: 1 broker; qa/prod: 3 brokers + TLS/SCRAM
        - [x] Kafka `4.2.0` (`quay.io/strimzi/kafka:1.2.0-kafka-4.2.0`);
              `KafkaNodePool` owns storage/resources/JVM/anti-affinity
        - [x] internal listener `9092` is TLS + SCRAM-SHA-512; simple
              authorization with `scram-admin` as superUser
        - Commits: `feat(db): add strimzi kafka cluster with scram auth and node pools`
  - [x] SCRAM-SHA-512 users + listeners
        - [x] credentials projected by ESO from `secret/kafka/<env>`
              (`username=scram-admin`, generated `password`) into
              `kafka-scram-admin`; the `KafkaUser` references that Secret via
              `spec.authentication.password.valueFrom.secretKeyRef`
        - [x] dedicated raw `Application` per env (`argocd/kafka-<env>.yaml`,
              `directory.include: "*-<env>.yaml"`), wave 40
        - Commits: `feat(db): add strimzi kafka cluster with scram auth and node pools`
  - [x] smoke: topic create/produce/consume over SCRAM
        - [x] `smoke-kafka.sh` waits for the `ExternalSecret`, `Kafka`,
              `KafkaUser` and brokers, then creates a topic, produces and
              consumes one record through SASL_SSL/SCRAM-SHA-512
        - Commits: `test(kafka): add smoke test for kafka event backbone`,
              `fix(kafka): select broker pods by pool-name label`
  - [x] docs: Work Log row + catalog Status → deployed
        Commits: `docs(kafka): mark deployed`
  Issue done when: brokers `Running` + SCRAM produce/consume works.

Notes:

- `local`/`dev` run one dual-role (`controller,broker`) node with 1/2 GiB
  storage and `default.replication.factor`/`min.insync.replicas` `1/1`;
  `qa`/`prod` run three nodes with 10/20 GiB each, replication `3` and
  `min.insync.replicas` `2`. The qa/prod nodes use `preferred` pod anti-affinity
  so the profile remains schedulable on the single-node promote substrate.
- The Kafka cluster is a dedicated raw `Application` per environment (not in the
  Helm `ApplicationSet`) because the Strimzi `Kafka`/`KafkaNodePool`/`KafkaUser`
  resources are CRs, not a chart. The catalog preload resolves the Kafka image
  from the raw manifests.
- Vault is the password source of truth: the `ExternalSecret` projects
  `secret/kafka/<env>` into `kafka-scram-admin`, and the User Operator consumes
  the same Secret. The seed script writes the path on the local profile.

No natural further phases → issues stay under M1.
