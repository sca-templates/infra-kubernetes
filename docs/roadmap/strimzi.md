# Project: Implement Strimzi

Area: Data · Wave -10 · Environments: local→dev→qa→prod
Depends on: — (operator only, wave -10)
Project done when: `strimzi-kafka-operator` `Running`; a `Kafka`/`KafkaNodePool`
review shows the CRs are honored (data project #11 waits on it).

No natural phases → issues directly under the project.

- [ ] Issue #6 · Deploy `strimzi/strimzi-kafka-operator`
  Depends on: —
  - [ ] `infrastructure/strimzi/` values-base + overlays for 4 envs
        - [ ] envs/local, dev, qa, prod
        - Commits: `feat(strimzi): add chart reference and per-env overlays`
  - [ ] registry appset element (wave -10)
        Commits: `feat(strimzi): register in apps appset (wave -10)`
  - [ ] smoke: operator pod `Running`, Kafka CR groups present
        Commits: `test(strimzi): operator smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(strimzi): mark deployed`
  Issue done when: operator pod `Running` + CRDs present.
