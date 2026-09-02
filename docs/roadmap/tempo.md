# Project: Implement Tempo

Area: Observability · Wave 60 · Environments: local→dev→qa→prod
Depends on: cert-manager (#1); MinIO (#17, local) for storage where applicable.
Project done when: Tempo ingests OTLP traces; a trace is queryable; Grafana shows
traces correlated with logs/metrics.

No natural phases → issues directly under the project.

- [ ] Issue #16 · Deploy `grafana/tempo`
  Depends on: cert-manager (#1)
  - [ ] `infrastructure/tempo/` values-base + overlays for 4 envs
        - [ ] envs/local, dev, qa, prod
        - Commits: `feat(tempo): add chart reference and per-env overlays`
  - [ ] OTLP ingestion + storage
        Commits: `feat(tempo): otlp ingestion`
  - [ ] smoke: send a test trace, query it back
        Commits: `test(tempo): trace query smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(tempo): mark deployed`
  Issue done when: test trace round-trips through Tempo.
