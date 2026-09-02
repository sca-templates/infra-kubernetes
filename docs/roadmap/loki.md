# Project: Implement Loki + Alloy

Area: Observability · Wave 60 · Environments: local→dev→qa→prod
Depends on: cert-manager (#1); storage on MinIO (#17, local) once available —
`loki` config references the MinIO S3 endpoint.
Project done when: Loki ingests; Alloy ships pod logs to Loki; logs queryable
across namespaces.

## Milestone M1 — Loki

M1 done when: Loki `Running`, a log line is queryable.

- [ ] Issue #15 · Deploy `grafana/loki`
  Depends on: cert-manager (#1)
  - [ ] `infrastructure/loki/` values-base + overlays for 4 envs
        - [ ] envs/local, dev, qa, prod
        - Commits: `feat(loki): add chart reference and per-env overlays`
  - [ ] storage: MinIO S3 (local) or PVC/per-env store
        Commits: `feat(loki): storage configuration`
  - [ ] smoke: `logcli query` returns a pod log line
        Commits: `test(loki): log query smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(loki): mark deployed`
  Issue done when: Loki queries a shipped log line.

## Milestone M2 — Alloy

M2 done when: pod logs appear in Loki across namespaces.

- [ ] Issue #15-2 · Deploy `grafana/alloy` (log shipping)
  - [ ] `infrastructure/alloy/` values-base + overlays for 4 envs
        - Commits: `feat(alloy): add chart reference and per-env overlays`
  - [ ] pod-log wiring to Loki
        Commits: `feat(alloy): ship pod logs to loki`
  - [ ] smoke: a freshly written pod log is queryable in Loki
        Commits: `test(alloy): log ship smoke`
  Issue done when: cross-namespace logs land in Loki.
