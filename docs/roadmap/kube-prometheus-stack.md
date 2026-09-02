# Project: Implement kube-prometheus-stack

Area: Observability · Wave 60 · Environments: local→dev→qa→prod
Depends on: cert-manager (#1) for TLS; linkerd (#9) for mesh golden signals.
Project done when: Prometheus/Grafana/Alertmanager deployed; radar alerts
configured per [observability-radar.md](../observability-radar.md); `make
status` shows no new `Degraded`.

## Milestone M1 — Stack

M1 done when: Prometheus `ProbablyHealthy`, Grafana reachable, Alertmanager ok.

- [ ] Issue #14 · Deploy `kube-prometheus-stack`
  Depends on: cert-manager (#1), linkerd (#9)
  - [ ] `infrastructure/kube-prometheus-stack/` values-base + overlays 4 envs
        - [ ] envs/local, dev, qa, prod
        - Commits: `feat(kube-prometheus-stack): add chart reference and per-env overlays`
  - [ ] alertmanager + Grafana ingress via Kong with TLS
        Commits: `feat(kube-prometheus-stack): alerts and grafana ingress`
  - [ ] smoke: Prometheus target up; Grafana dashboard loads
        Commits: `test(kube-prometheus-stack): prometheus and grafana smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(kube-prometheus-stack): mark deployed`
  Issue done when: Prometheus `ProbablyHealthy` + Grafana reachable.

## Milestone M2 — Radar

M2 done when: radar alert rules evaluated; notifications reach the configured
receiver.

- [ ] Issue #14-2 · Radar alerts + notification routing
  - [ ] radar alert rules per [observability-radar.md](../observability-radar.md)
        Commits: `feat(kube-prometheus-stack): radar alert rules`
  - [ ] route/notification to the configured receiver
        Commits: `feat(kube-prometheus-stack): alert routing`
  - [ ] smoke: alert rule metric evaluates; receiver gets a test notification
        Commits: `test(kube-prometheus-stack): radar alert smoke`
  Issue done when: a radar alert fires and reaches the receiver.
