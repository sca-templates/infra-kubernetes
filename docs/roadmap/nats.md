# Project: Implement NATS JetStream

Area: Data · Wave 40 · Environments: local→dev→qa→prod
Depends on: none (upstream chart); NACK (#105) connects to it.
Project done when: the NATS server is `Ready` with JetStream enabled, the tier
ships no `Stream`/`Consumer` CRs, and the idle smoke is green.

## Milestone M1 — idle JetStream tier

M1 done when: the server is stable and JetStream reports enabled with zero
streams (1 node local/dev, 3-node JetStream cluster qa/prod).

- [x] Issue #105 · NATS server + JetStream
  Depends on: none
  - [x] `infrastructure/nats/` values + `envs/<env>/nats.yaml` overlays
        - [x] chart/appVersion `nats/nats` `2.15.2`; file-store PVC
              (1/2/5/10 GiB) and `max_file_store`
        - [x] local/dev: 1 node; qa/prod: 3-node JetStream cluster + PDB +
              preferred anti-affinity (under `podTemplate.merge.spec.affinity`)
        - [x] sidecars pinned to the chart defaults (`reloader` 0.24.0,
              `nats-box` 0.20.0)
  - [x] `ApplicationSet` element (name `nats`, namespace `data`, wave 40)
        - [x] no `Stream`/`Consumer` CRs in git: the tier is ready but idle
  - [x] smoke: server Ready, JetStream enabled, zero streams
        - [x] `bootstrap/smoke-nats.sh` (`make smoke COMPONENT=nats`)
  - [x] docs: Work Log row + catalog Status → deployed

Notes:

- NATS is the ADR-005 replacement for Kafka/Strimzi. It lands **idle**: the
  server and its file store are ready, but the declarative JetStream resources
  arrive per consumer (reconciled by NACK) once the toggle and the consumers
  exist. No client auth in this tier yet; the server is reachable only
  in-cluster (`nats.data.svc.cluster.local:4222`).
- Kafka/Strimzi remain deployed until the removal commit, so the platform runs
  both backbones while the migration is in progress.
- `local`/`dev` run one node (no JetStream R3); `qa`/`prod` run three with a PDB
  and `preferred` anti-affinity so the profile stays schedulable on the
  single-node promote substrate.
