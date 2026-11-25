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
  - [x] optional `ApplicationSet` element (name `nats`, namespace `data`, wave 40)
        - [x] descriptor `argocd/messaging/<env>/nats.yaml`
        - [x] no `Stream`/`Consumer` CRs in git: the tier is ready but idle
  - [x] smoke: server Ready, JetStream enabled, zero streams
        - [x] `bootstrap/smoke-nats.sh` (`make smoke COMPONENT=nats`)
  - [x] docs: Work Log row + catalog Status → deployed

Notes:

- NATS is the ADR-005 event backbone. It lands **idle**: the server and its file
  store are ready, but the declarative JetStream resources arrive per consumer
  (reconciled by NACK) once the consumers exist. No client auth in this tier
  yet; the server is reachable only in-cluster
  (`nats.data.svc.cluster.local:4222`).
- Kafka/Strimzi were removed in C3, leaving NATS/NACK as the sole event
  backbone. The C4 toggle runbook and service-owned topology guide are in
  [messaging.md](../messaging.md).
- `local`/`dev` run one node (no JetStream R3); `qa`/`prod` run three with a PDB
  and `preferred` anti-affinity so the profile stays schedulable on the
  single-node promote substrate.

## Milestone M2 — SNS/SQS vs NATS toggle

M2 done when: each environment can switch backends from git alone, the NATS
ApplicationSet disappears in SNS/SQS mode, and consumers have a stable
endpoint/credential contract.

- [x] Issue #105 · optional `messaging-<env>` `ApplicationSet`
  - [x] git files generator over `argocd/messaging/<env>/*.yaml`
  - [x] `nats.yaml` + `nack.yaml` descriptors present in NATS mode (all envs)
  - [x] removing the descriptors switches that env to SNS/SQS (nothing in-cluster)
  - [x] `resources-finalizer` prunes the Applications/resources on removal
- [x] messaging contract `secret/messaging/<env>` (KV-v2)
  - [x] `mode` + `nats_url`; SNS/SQS coordinates provisioned out of band
  - [x] local seed in `bootstrap/seed-vault.sh`
- [x] platform wiring
  - [x] `argocd/messaging-<env>.yaml` applied by `make bootstrap`
  - [x] image preload resolves the optional descriptors
  - [x] `smoke-ci.sh` gates NATS/NACK only when the local descriptors exist

Notes:

- The mandatory platform list (`argocd/apps-<env>.yaml`) no longer owns
  NATS/NACK. The optional ApplicationSet uses the same app names
  (`nats-<env>`/`nack-<env>`), so smokes and catalog discovery are unchanged.
- The toggle is at descriptor-file level rather than a Helm values flag: the
  platform list generator cannot express a per-env optional component, and a
  git files generator makes the file set in git the single source of truth.
- Follow-up (first consumer): enable NATS accounts/credentials and extend the
  contract; no consumer exists yet, so the tier stays unauthenticated. See
  [messaging.md](../messaging.md) for the procedure boundary.
