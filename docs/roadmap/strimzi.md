# Project: Implement Strimzi

Area: Data · Wave -10 · Environments: local→dev→qa→prod
Depends on: — (operator only, wave -10)
Project done when: `strimzi-cluster-operator` `Running`; a `Kafka`/
`KafkaNodePool` review shows the CRs are honored (data project #11 waits on it).

No natural phases → issues directly under the project.

- [x] Issue #11 · Deploy `strimzi/strimzi-kafka-operator`
  Depends on: —
  - [x] `infrastructure/strimzi/` values-base + overlays for 4 envs
        - [x] envs/local, dev, qa, prod
        - Commits: `feat(strimzi): add chart reference and per-env overlays`
  - [x] registry appset element (wave -10)
        - Commits: `feat(strimzi): register in apps appset (wave -10)`
  - [x] smoke: operator pod `Running`, Kafka CR groups present
        - Commits: `test(strimzi): operator smoke`
  - [x] docs: Work Log row + catalog Status → deployed
        - Commits: `docs(strimzi): mark deployed`
  Issue done when: operator pod `Running` + CRDs present.

Rollout notes:

- Chart pinned at 1.2.0 (appVersion 1.2.0, `quay.io/strimzi/operator:1.2.0`)
  across all 4 envs; the 10 `kafka.strimzi.io` / `core.strimzi.io` CRDs ship in
  the chart's `crds/` bundle. No one-off cluster hygiene was needed: the
  2026-09-02 bulk-install leftovers for this group were already removed during
  the CloudNativePG pass (see `docs/architecture.md` deviations log), so the app
  created its CRDs as app-owned and converged without the `OutOfSync` wedge.
- `watchAnyNamespace: true` in the base values: the Kafka datastores run in
  `data` (Phase 11), not in `strimzi`. Same reasoning as CloudNativePG's
  `config.clusterWide`; the operator's RBAC is cluster-wide either way.
- The `qa`/`prod` overlays null the chart's `minAvailable: 1` default
  explicitly. The chart renders whichever field is set, and the Kubernetes API
  rejects a PodDisruptionBudget that sets both `minAvailable` and
  `maxUnavailable`, so the budget is expressed as `maxUnavailable: 1` only.
