# Project: Implement Kong

Area: Edge & Mesh · Wave 20 · Environments: local→dev→qa→prod
Depends on: cert-manager (#6) — TLS for the gateway edge.
Project done when: Kong gateway serves a route with TLS via cert-manager; DB-less
config is in git; the dedicated Application has no SSA (`ServerSideApply`: off).

## Milestone M1 — Gateway deployment

M1 done when: pod `Running`, app `Synced`/`Healthy`.

- [x] Issue #13 · Deploy `kong/kong` (DB-less, dedicated Application, no SSA)
  Depends on: cert-manager (#6)
  - [x] `infrastructure/kong/` values-base + overlays for 4 envs
        - [x] envs/local, dev, qa, prod
        - Commits: `feat(kong): add chart reference and per-env overlays`
  - [x] dedicated Application with `syncOptions` SSA disabled
        Commits: `feat(kong): dedicated application without SSA`
  - [x] DB-less config (declarative routes) in git
        Commits: `feat(kong): declarative db-less configuration`
  - [x] smoke: Gateway receives a route + TLS certificate served
        Commits: `test(kong): route and tls smoke`
  - [x] docs: Work Log row + catalog Status → deployed
        Commits: `docs(kong): mark deployed`
  Issue done when: gateway route works + TLS via cert-manager.

No natural further phases → issues stay under M1.

Rollout notes:

- Chart pinned at 3.4.1 (`kong/kong` from `https://charts.konghq.com`) across all
  4 envs, with the gateway image pinned `kong:3.9.4` and the bundled Kubernetes
  Ingress Controller `kong/kubernetes-ingress-controller:3.5.5` (both would
  otherwise float on the chart's `3.9`/`3.5` defaults, which the image policy
  forbids). `fullnameOverride: kong` keeps the Services `kong-proxy` /
  `kong-admin` and runs the gateway + controller as one Deployment (`kong`).
- Kong runs **DB-less** (`env.database: off`): no Postgres, no migrations, no
  drift — routing is declared in git and programmed by the Ingress Controller.
- **Dedicated `Application` per env (`kong-<env>`), no `ServerSideApply`.** The
  platform `ApplicationSet` forces `ServerSideApply=true`, which breaks the
  structured-merge diff on Kong's flat-schema `configuration.konghq.com` CRDs;
  the dedicated app leaves SSA off and otherwise mirrors the catalog template
  (multi-source: chart + `$values` ref + `infrastructure/kong/manifests`, the
  standard CRD `ignoreDifferences`, per-env sync policy). See
  [architecture.md](../architecture.md#deviations-log).
- `ingressController.installCRDs: false`: the chart's templated CRD copy stays
  off and ArgoCD applies the chart's `crds/` bundle via `--include-crds`
  (enabling it would emit every CRD twice). `certificates.proxy` wires a
  cert-manager leaf `kong-proxy` / `kong-proxy-cert` from the `sca-ca`
  ClusterIssuer (SANs `kong.local` + `localhost`); `certificates.admin` and
  `certificates.cluster` stay off (the admin listener is plaintext and there is
  no hybrid CP/DP pair).
- The declarative route reference (`infrastructure/kong/manifests/`) is a
  committed `Ingress` on `ingressClassName: kong` plus a `request-termination`
  `KongPlugin` — a pure echo (no backing workload, no extra image), and the
  pattern service charts follow (`charts/service-template` uses
  `ingress.className: kong`). The admin Service the Ingress names is never
  reached (the plugin terminates the request first).
- Footprint: `local` 1 replica / NodePort 30080/30443 (on the local node the
  ports are reached from the host via a port-forward); `dev` 1 replica / LoadBalancer; `qa`/`prod` 2 replicas /
  LoadBalancer with a PodDisruptionBudget (`maxUnavailable: 1`) and soft
  anti-affinity. The gateway is stateless, so prod differs from qa only by its
  manual sync tier.
- Smoke (`make smoke COMPONENT=kong`): gateway Deployment Ready + DB-less
  (`KONG_DATABASE=off`) + IngressClass `kong` + `configuration.konghq.com` CRDs
  `Established` + the `kong-proxy` Certificate Ready + a TLS request to
  `https://kong.local/demo` returning 200, validated against the `sca-ca` chain.
