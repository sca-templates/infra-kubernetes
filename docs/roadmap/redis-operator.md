# Project: Implement redis-operator

Area: Data · Wave -10 · Environments: local→dev→qa→prod
Depends on: — (operator only, wave -10)
Project done when: `redis-operator` `Running`; a `Redis` CR review shows the
CR is honored (data project #17 waits on it).

No natural phases → issues directly under the project.

- [x] Issue #12 · Deploy `ot-container-kit/redis-operator`
  Depends on: —
  - [x] `infrastructure/redis-operator/` values-base + overlays for 4 envs
        - [x] envs/local, dev, qa, prod
        - Commits: `feat(redis-operator): add chart reference and per-env overlays`
  - [x] registry appset element (wave -10)
        - Commits: `feat(redis-operator): register in apps appset (wave -10)`
  - [x] smoke: operator pod `Running`, Redis CR group present
        - Commits: `test(redis-operator): operator smoke`
  - [x] docs: Work Log row + catalog Status → deployed
        - Commits: `docs(redis-operator): mark deployed`
  - [x] local tooling unblocked for the clean-cluster reset (same PR, not phase
        scope: found while resetting the kind cluster to validate the smoke)
        - Commits: `fix(makefile): drop the unsupported kind delete flag from cluster-down`, `fix(local-git): create the git-serve namespace and retry the reachability probe`
  Issue done when: operator pod `Running` + CRD present.

Rollout notes:

- Chart pinned at 0.26.1 (appVersion 0.26.0, `quay.io/opstree/redis-operator`)
  across all 4 envs; the 4 `redis.redis.opstreelabs.in` CRDs (`redis`,
  `redisclusters`, `redisreplications`, `redissentinels`) ship in the chart's
  `crds/` bundle, so the app creates them as app-owned and converges without the
  `OutOfSync` wedge the 2026-09-02 bulk-install leftovers used to cause (those 4
  were already removed in the CloudNativePG pass, see `docs/architecture.md`
  deviations log). The image tag is pinned explicitly to `v0.26.0` (upstream
  publishes the `v` prefix; the chart would otherwise compose it from appVersion)
  and `imagePullPolicy` is set to `IfNotPresent` instead of the chart's `Always`.
- **The chart moved host upstream.** The documented repo
  `https://charts.ot-container-kit.io` no longer resolves — the domain answers
  `NXDOMAIN` authoritatively for `io` (checked against public DNS on 2026-09-27),
  which wedged the app in `ComparisonError: failed to fetch chart`. The
  maintainers now publish the same charts from their GitHub Pages repo, so
  `chartRepo` is pinned to `https://ot-container-kit.github.io/helm-charts`
  (same publisher, same versions; `redis-operator` 0.26.1 → appVersion 0.26.0
  with an identical digest). ArgoCD reaches it from the cluster as any other
  `https://` chart repo. The pin guards in `security.yml` are unaffected: they
  reject floating `targetRevision`/tags, not the host.
- The operator is installed in the **`data` namespace**, sharing it with the
  datastores it will manage, instead of a namespace of its own like Strimzi's
  and CloudNativePG's — it is the first app to create `data` (via
  `CreateNamespace=true`). `redisOperator.watchNamespace: ""` is left empty on
  purpose: the chart then renders **no** `WATCH_NAMESPACE` env at all, which is
  its way of saying "every namespace", so the Phase 12 CRs can live wherever they
  are meant to. Same reasoning as Strimzi's `watchAnyNamespace` and
  CloudNativePG's `config.clusterWide`.
- **No PodDisruptionBudget** in the `qa`/`prod` overlays (2 replicas + soft
  anti-affinity each): this chart ships no PDB value, so a budget would mean a
  raw manifest in an env-agnostic `manifests/` directory that would also apply to
  `local`. The operator is stateless and leader-elected, so a voluntary eviction
  only re-elects a leader. The chart's **webhook stays off** too — it gates
  `masterSlaveAntiAffinity` only, and nothing in the platform uses master/slave
  anti-affinity (Sentinel and cluster topologies arrive as their own CRs at
  Phase 12).
- The smoke is the deepest one so far, because the `Redis` CRD declares an
  **empty status object** (no conditions to assert): besides the operator
  Deployment and the 4 CRDs `Established`, `make smoke COMPONENT=redis-operator`
  applies a throwaway `Redis` CR in a scratch namespace and requires the
  operator to honor it — StatefulSet ready, pod running, `redis-cli PING` →
  `PONG` — then deletes the namespace. The throwaway pins
  `kubernetesConfig.image: quay.io/opstree/redis:v7.4.11`; upstream's own example
  ships `:latest`, which the pinned-tags policy forbids, so **the Phase 12 `Redis`
  CR must pin `kubernetesConfig.image` (and leave `redisExporter` alone or pin it
  too) or the pin guards in `security.yml` will not be the only thing to catch
  it**. The throwaway omits `redisExporter` entirely: the CRD lists `image` as
  required for that block, so `enabled: false` alone is rejected by the CR
  schema, and a disabled-but-present block would drag in a second image pin for a
  disposable instance.
- `redisOperator.metrics.enabled` stays on: the operator serves its own `:8080`
  metrics, but the chart renders no Service for them, so nothing scrapes the
  endpoint until Phase 14 adds a PodMonitor for the `data` namespace. The Redis
  instances' own exporter (`redisExporter`) belongs to the Phase 12 CR, not
  here.
