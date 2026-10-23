# CI/CD

What GitHub Actions do — and deliberately do **not** — do for this
repository. Phase 0 ships the static workflows plus the release automation
(no cluster smoke); **Phase 1 ships the cluster-smoke workflow
(`pr-cluster.yml`)**, rebuilt from scratch, run on Floci's emulated EKS
substrate and gating PRs as the **required `Smoke` check** on `main`. See [security.md](security.md) for the security controls these
workflows carry, [versioning.md](versioning.md) for how releases, tags and the
CHANGELOG are produced, and [workflow.md](workflow.md) for how a merge becomes
a deployment.

## Shipped workflows

| Workflow | File | Runs on | What it does |
| --- | --- | --- | --- |
| Validate | `.github/workflows/validate.yml` | push + PR | **wrapper** over the shared template (markdownlint, yamllint, `bash -n`, actionlint) plus a local `Kubernetes and Helm` job (kubeconform/kube-linter on `infrastructure/` and the Helm service template); the static-suite checks now have a template counterpart, manifest lint stays local |
| Security | `.github/workflows/security.yml` | push + PR | **wrapper** over the shared template: gitleaks, osv-scanner (SCA) and checkov (static IaC baseline); only the pin guards (no `latest` tags/charts) stay local |
| CodeQL | `.github/workflows/codeql.yml` | push + PR + schedule | GitHub CodeQL static analysis on the repo languages — **wrapper** over the shared template |
| Release | `.github/workflows/release.yml` | push to `main` | **wrapper** over the shared template with `latest-policy: hold`: release-please opens release PRs/tags (+ signed annotated tags) and **draft** GitHub Releases for `feat`/`fix` commits touching the **platform surface** — commits confined to the `exclude-paths` directories (`.github`, `bootstrap`, `0.Project_info`) are dropped (see [versioning.md](versioning.md)); drives `CHANGELOG.md`; no manual re-sign `workflow_dispatch` (see [versioning.md](versioning.md)). The template's `hold` policy captures the previous `latest` and finalizes the release **off** `latest`, re-asserting the previous pointer |
| Release promote | `.github/workflows/release-publish.yml` | manual | **local**: the only thing that ever moves `latest` **forward** (`finalize` only re-states it on the previous release). Moves the pointer for a signed, adopted tag, after verifying the tag is annotated and signed by the release bot (see [versioning.md](versioning.md)) |
| Release gate | `.github/workflows/release-gate.yml` | PR + manual | **wrapper** over the shared template: blocks PRs while a release-please PR is open (`release-gate / release-gate` required check) |
| Auto label | `.github/workflows/auto-label.yml` | PR | **wrapper** over the shared template: labels PRs from the type (`feature`, `bug`, `ci`, `documentation`, `refactor`, `security`, `dependencies`) and changed files — see [labels.md](labels.md) |

### Template provenance

The named **wrapper** workflows delegate their logic to reusable workflows in
[sca-templates/CI-CD-Templates](https://github.com/sca-templates/CI-CD-Templates),
referenced **pinned to a commit SHA** (this repo's strict-pin policy; the
template repo recommends `@main`). `Validate` →
`shared-validate.yml`, `CodeQL` → `shared-codeql.yml`,
`Security` (gitleaks + osv + checkov) →
`shared-security-scan.yml`, `Release` → `shared-release-flow.yml` (with
`latest-policy: hold`), Release gate
→ `shared-qa-lock-check.yml`, Auto label → `shared-auto-label.yml`. The templates' own pins (actions, versions,
`mint-app-token` composite) are maintained by the template repo's dependabot;
this repo keeps its remaining local action pins current via its own
[`.github/dependabot.yml`](../.github/dependabot.yml). `pr-cluster.yml`,
`main-sync.yml` and `deploy.yml` stay local on purpose: the cluster
smoke/EKS-parity pipelines are repo-specific and have no template counterpart.
The Kubernetes/Helm manifest lint inside `validate.yml` also stays local for
the same reason; the `Kubernetes and Helm` job lives in the caller next to the
`shared-validate.yml` call. `Security`'s pin guards are the other local
hold-out. The `latest` hold (`capture` + `finalize`) that used to be local now
ships inside the shared flow's `latest-policy: hold`, so `release.yml` is a
plain wrapper.

### Scope semantics

- `validate.yml` runs the same checks locally via `make validate-static`
  (`bootstrap/sca.sh` installs the pinned CLI; no cluster required).
- `security.yml` guards run against the whole tree on every PR; the checkov
  **baseline** (`.github/checkov-baseline.json`) gates new findings — existing
  entries are documented, intentional manifests (see
  [security.md](security.md)).
- Workflows are scoped to the paths they own (docs/CI config), so a pure
  documentation PR does not re-run IaC scanning unnecessarily.

## Local toolchain CLI

`bootstrap/sca.sh` is the POSIX platform CLI (Linux distro-agnostic, macOS and
WSL2; Windows-native fails fast — use WSL2). The Makefile targets are thin
wrappers around it; `make install-cli` symlinks it as `~/.local/bin/sca`.

| Command | What it does |
| --- | --- |
| `sca prereqs` | Install pinned kubectl/helm into `~/.local/bin` — idempotent, sha256-verified, no sudo. Detects OS/arch (linux/darwin, amd64/arm64) and picks the matching upstream URLs; external deps (git, docker — the latter required for the Floci emulator) are reported with install hints but never installed |
| `sca doctor` | Read-only health: toolchain versions vs pins, PATH, docker, git, git source reachability, cluster, ArgoCD app sync/health, and the `.env` seam. Never mutates — run it first when something is off |
| `sca version` | Print the pinned toolchain versions |

Versions are pinned once in `bootstrap/versions.sh` (sourced by `sca.sh`);
`.env`/environment overrides still win. The darwin install path follows the
upstream URL patterns but is not yet exercised on hardware — see the pin
guards in [security.md](security.md).

### Release workflow

`release.yml` is a thin wrapper over the org shared
`shared-release-flow.yml`, run with `latest-policy: hold`. The template runs:

- **release-please** — runs **only on a push to `main`**; computes the next
  version, opens or updates the release PR, and on merge creates the tag and
  the GitHub Release as a **draft**. Commits whose files all fall under an
  `exclude-paths` directory are dropped before parsing, so a
  CI/tooling/docs-only push releases nothing.
- **sign-tag** — runs when a release was created on `main`; re-creates the tag
  as an annotated tag signed by the release-bot GPG key on the same commit. A
  manual re-sign via `workflow_dispatch` is **no longer offered** (the old
  `v0.1.0` lightweight tag was promoted with it once; the shared template
  covers only the push path — see [versioning.md](versioning.md)).
- **capture** (hold policy) — runs on the same push. It snapshots the release
  that was `latest` *before* this push, excluding the tag the push is about to
  cut, which is what makes the snapshot correct on a re-dispatched run too. It
  never blocks the release: it hands `finalize` a hint, and `finalize` decides
  what a missing hint means.
- **finalize** (hold policy) — runs after `release-please`. It is what makes
  the tag safe to have cut automatically while `latest` stays a human decision;
  see below.

The draft does not survive the shared flow: `sign-tag` replaces the tag by
force-push, and that rewrite publishes the draft. Declining `latest` afterwards
is not enough on its own — `make_latest=false` stores no pointer, so
`GET /releases/latest` falls back to the newest published release, which is the
one just published. `finalize` therefore publishes the release with
`{"draft": false, "make_latest": "false"}` in a single PATCH, re-designates the
captured previous release with `{"make_latest": "true"}` (the only call that
actually moves the pointer, and it has to be repeated on every release because
publishing clears the previous designation), and then re-reads
`/releases/latest` to confirm the result. The result is a public, full release
that is **not** `latest`, with the previous release still holding it.

`release-publish.yml` (local, `workflow_dispatch`) is the promotion step: it
verifies the tag is annotated and signed by the release bot, then moves the
`latest` pointer **forward**, onto the adopted release. It is the only step in
the repository that does so. See [versioning.md](versioning.md) for the rule,
the guards, and the measurements behind the two PATCHes.

The workflow is the only one that holds repository secrets
(`APP_ID`, `APP_PRIVATE_KEY`, `RELEASE_GPG_PRIVATE_KEY`) — see
[secrets.md](secrets.md) for how they are stored and rotated. Inside the shared
flow, `release-please` and the tag push authenticate as the org-owned
`sca-bot-release` GitHub App via a per-run installation token minted with the
`mint-app-token` composite action (scoped to `infra-kubernetes`), so release
PRs/tags are authored by `sca-bot-release[bot]` and still trigger the required
checks.

## Cluster smoke (`pr-cluster.yml`, Phase 1)

`pr-cluster.yml` is **absent** from Phase 0 because the previous attempt's
cluster-smoke CI had become a stack of hacks (trimmed manifests, self-heal
disabled) and burned a week in `fix` churn. It lands at **Phase 1** with
cert-manager, so each subsequent component is validated incrementally on a
live Floci emulated EKS substrate as it ships, and the deployed baseline is continuously
monitored. See the [roadmap](roadmap.md) for the Phase 1 gate and its smoke.

**Triggers:**

- **`pull_request`** — selective smoke of the touched component(s) (profile
  `local`), so a change is validated before it merges. A PR that touches more
  than one component smokes all of them in a single run (one cluster boot, one
  cloud bring-up, one teardown). Same-repo PRs only (fork PRs are skipped,
  coherent with `main-sync.yml`). The `Smoke` check is a **required**
  branch-protection check on `main`. There is a **single substrate**: the one
  `Smoke` job boots the whole platform catalog on the Floci emulated **EKS**
  substrate (*EKS substrate smoke* below) and requires every Application to
  converge `Synced`/`Healthy`, with Vault seeded before the health gate.
- **`workflow_dispatch`** (manual) — one-off smoke of a component/ref
  (`component` + `ref` inputs, defaults `cert-manager`/`main`) for testing
  without opening a PR. Nothing else triggers the workflow; there is no
  vigilance run on `push`.

The whole boot → apply → wait → run → diagnose → teardown cycle lives in
`bootstrap/smoke-ci.sh`; each component adds only its own smoke command
(`bootstrap/smoke-<component>.sh`, dispatched by `smoke-target.sh`).
`smoke-ci.sh` takes a **comma-separated** component list (`cert-manager,vault`)
and keeps a single-component run working unchanged: the cluster boots once, the
cloud emulator comes up once, each component's `<name>-smoke` Application is
applied/waited/smoked in turn, the cloud smoke runs once, every Application is
re-checked `Synced/Healthy` post-smoke, and teardown runs once. Wait steps
default to a 1200s timeout (`SMOKE_TIMEOUT`, overridable). Layered on top, the
framework also stands up and checks the cloud emulator (**on by default**;
`--no-cloud` / `SMOKE_CLOUD=0` opts out) — see *Cloud integration smoke* below.

The selective mapping in `pr-cluster.yml` resolves **every** changed path to a
component and smokes the whole set: `infrastructure/<c>/…` and
`envs/<env>/<c>.yaml` → `<c>`; `bootstrap/smoke-<c>*.sh` → `<c>` (the
`smoke-cloud*` scripts → `cloud`; `smoke-eks.sh` → `cert-manager`, exercised by
the always-on EKS step); `bootstrap/cloud-emulator.sh` →
`cloud`; `bootstrap/eks-emulator.sh` → `cert-manager` (exercised by the EKS
substrate). Changes to the smoke's own machinery — `bootstrap/smoke-ci.sh`,
`smoke-target.sh`, `render-served-apps.sh`, `sca.sh`, `versions.sh`,
`local-git-*`, `preload-chart-images.sh`,
`collect-argocd-diagnostics.sh`, `argocd/**` and the `Makefile` — resolve to
the default component `cert-manager`, so the framework is exercised by the
smoke instead of merging untested.

`make argocd-up` and `make bootstrap` pre-pull the chart images with the host
Docker and load them into the EKS node (`bootstrap/preload-chart-images.sh`)
before Helm runs — a **catalog-wide** preload (`--catalog <env>` resolves the
images for every chart in the env's ApplicationSet plus the dedicated Kong and
Linkerd apps).
A node-side pull on an ephemeral runner can stall behind registry throttling past
a Deployment's `progressDeadlineSeconds`, surfacing as a flaky `argocd-up`
failure that no Helm `--timeout` can fix; pre-pulling takes the registry off the
critical path. The pulled images are cached between runs as a docker-image
tarball under `~/.cache/sca/preload` (`PRELOAD_CACHE_DIR`), which the workflow
restores/saves with `actions/cache` (keyed on the pins, the catalog manifests and
the renderer), so a throttled public registry is never on the critical path. This
is dev/CI tooling, not a platform component. If `argocd-up`
still fails, `bootstrap/collect-argocd-diagnostics.sh` dumps the ArgoCD install
state (pods, describe, events) into `.generated/` — the framework's `diagnose`
runs only *after* ArgoCD is up, so an install-time failure would otherwise carry
no evidence.

On failure the diagnose step captures the Application(s)/ApplicationSet state,
pod describe + logs, EndpointSlices, recent cluster events, the Applications'
managed/syncResult resources and node conditions/pressure, and the workflow
uploads `.generated/` as an artifact (`if: always()`), so a non-green run is
self-explanatory. The pinned toolchain (`~/.local/bin`) is also cached with
`actions/cache`, keyed on `bootstrap/versions.sh`, so a pin bump invalidates it
and `make prereqs` stays idempotent (a full cache hit is a no-op).

### Design properties

- **Full platform, single substrate**: boots the whole platform catalog on the
  Floci emulated EKS substrate and smokes *only* the
  component(s) the PR touches (plus any already-shipped dependency they need),
  while every Application in the catalog must converge `Synced`/`Healthy`. A PR
  touching several components smokes all of them
  in one run. Changes to the smoke framework itself resolve to `cert-manager`,
  so the machinery is never merged untested. A docs-only PR skips the cluster
  entirely.
- **No trim hacks**: the smoke runs the real chart/CR, not a reduced copy.
- **No self-heal disabling**: ArgoCD auto-reconcile stays on during the smoke;
  the component is applied via its ArgoCD `Application`, letting ArgoCD converge
  and reconcile on its own.
- **Incremental, not accumulative**: each smoke validates the touched component
  against an already-converged cluster; the framework (boot, apply, wait,
  diagnose, teardown) is shared and only the component-specific smoke command is
  added per phase.
- **Cloud-aware**: on top of the component smoke, every run also proves the
  cluster reaches a local cloud emulator (see *Cloud integration smoke* below) —
  so "does this platform talk to a cloud?" is answered on every PR, not only at
  a later cloud phase.
- **Two-phase convergence gate**: the framework first waits for the smoke
  `Application` to become **`Synced`** (any health), runs the component smoke,
  then waits for **`Synced/Healthy`**. Health is deliberately *not* a pre-smoke
  gate: stateful components (e.g. Vault) are born sealed/uninitialized and only
become `Healthy` after their own smoke seeds them (`smoke-vault.sh` →
   `seed-vault.sh`); requiring `Healthy` first would deadlock their bootstrap.
   Post-smoke `Healthy` is the real gate, so a genuinely broken chart/CR still
   fails the PR. Post-smoke `Degraded` is tolerated as a transient, not an
   instant fail: CRD-shipping apps (e.g. cloudnative-pg) are born `Degraded`
   while their CRDs still report `Established` — ArgoCD v3.x flags that as
   "CRD is not established" (argoproj/argo-cd#26346) — and self-heal on the
   next refresh. The gate is the wait deadline: the run fails only if the app
   has not converged to `Synced/Healthy` in time (genuine failures stay
   `Degraded` and hit the deadline with diagnostics).

  ArgoCD syncs synchronously (no `-Async` on the smoke ApplicationSet), so a
  `Deployment` that is slow becoming `Ready` blocks `Synced`. The cert-controller
  in external-secrets is the classic case: its `/readyz` waits on asynchronous
  CRD/webhook injection reconciles that can take minutes on a cold boot. The
  `local`/`dev` overlays therefore disable that readiness probe (the controller
  serves no traffic; the component smoke asserts real readiness) while `qa`/`prod`
  keep it.

### Cloud integration smoke (Floci — dev/CI tooling)

Every smoke also proves the cluster can reach and **operate against** an
emulated cloud, so cloud integration is exercised on each PR without a cloud
account, IAM material or per-cloud configuration. This is **CI/dev tooling, not
a platform component**: it has no sync-wave, no catalog row and nothing is
rendered by ArgoCD — it exists only for the duration of a smoke run.

- **Lifecycle** — `bootstrap/cloud-emulator.sh up|down|status [provider]`
  (wrapped as `make cloud-up` / `make cloud-down` / `make cloud-status`). It
  runs the emulator as a **Docker container on the runner/host**, attaches it to
  the EKS substrate's own Docker network, and publishes it into the
  cluster through a **selector-less `Service` + `EndpointSlice`** in the `cloud`
  namespace. In-cluster pods therefore reach it at the stable DNS name
  `http://floci.cloud.svc.cluster.local:4566` (host edge on `127.0.0.1:4566`).
- **The check** — `bootstrap/smoke-cloud.sh` dispatches by provider to
  `bootstrap/smoke-cloud-<provider>.sh` (`aws` today). The `aws` check throws a
  throwaway Job at the endpoint: the pinned AWS CLI creates an S3 bucket, puts
  and gets an object back and greps the round-tripped bytes (`AWS_SMOKE_OK`).
  No IAM, no per-component configuration — just an endpoint plus the same dummy
  credentials. Driven by `make smoke COMPONENT=cloud` (or
  `workflow_dispatch` with `component=cloud`).
- **Wiring** — `smoke-ci.sh` runs `make cloud-up` right after the cluster boots
  and `make smoke COMPONENT=cloud` right after the component smoke, on **every**
  smoke run (on by default). `--no-cloud` / `SMOKE_CLOUD=0` opts out. `cloud` is
  a smoke target, not an ArgoCD Application: a `cloud` entry in the component
  list skips `smoke-app`/wait (it has nothing to converge) and only runs the
  cloud check. A PR that touches the cloud
  tooling (`bootstrap/cloud-emulator.sh`, `bootstrap/smoke-cloud*.sh`) resolves
  to the `cloud` component, so the tooling is self-validated in CI; `cloud` is
  also selectable via `workflow_dispatch`.
- **Pins** — the emulator and CLI images are pinned in
  `bootstrap/versions.sh` (`FLOCI_IMAGE`, `AWS_CLI_IMAGE`), covered by the
  pin guards ([security.md](security.md)), and overridable via `.env`.
- **Adding a cloud** means a provider case in `cloud-emulator.sh` plus a
  `bootstrap/smoke-cloud-<provider>.sh` — nothing else changes.

The emulator is the **endpoint half** of cloud integration.

### EKS substrate smoke (Floci — dev/CI tooling)

The single `Smoke` job boots the **full platform**
on an **emulated EKS cluster** — the platform's only cluster substrate — and
proves the two EKS-specific paths a plain local cluster cannot: a real Kubernetes
API server reached through an
**IAM-authenticated kubeconfig**, and images **pulled in-cluster from the
emulated ECR**. Still **CI/dev tooling, not a platform component**: no
sync-wave, no catalog row, nothing rendered by ArgoCD (the k3s node and ECR are
Floci's EKS backing, not ArgoCD-managed).

- **Substrate** — Floci backs `eks` with a real single-node **k3s** container (a
  live API server) plus an OCI **ECR** registry. `bootstrap/eks-emulator.sh
  up|down|status` (`make eks-up` / `make eks-down` / `make eks-status`) starts
  Floci in EKS mode on a dedicated Docker network, mints an **IAM user + access
  key** (Floci rejects the dummy `test`/`test` creds for cluster-admin; the key
  is saved to `.secrets/eks-admin.env` and reused on re-run), `aws eks
  create-cluster` (issued once — the AWS CLI's own retries are off, because
  Floci's create is not idempotent while it provisions k3s and a retried request
  provisions a second k3s container; the script then converges on the cluster
  state instead of trusting the call's verdict), waits `ACTIVE`, fetches the
  kubeconfig (stable context `floci-eks`), waits for the node `Ready`, and
  publishes the emulator into the cluster for the endpoint smoke. `ACTIVE` alone
  is not trusted — Floci records the cluster row before the k3s node registers,
  and a create cut off server-side leaves that row `ACTIVE` with no node ever
  appearing, so the script waits a short window (`NODE_APPEAR_TIMEOUT`) for the
  first `Node` object and **recreates the cluster once** if none shows, instead
   of burning the full `SMOKE_TIMEOUT`. The kubeconfig is written with
   `aws eks update-kubeconfig --alias floci-eks`, and `${HOME}/.kube` is
   pre-created as the invoking user (and chowned back if the container wrote it
   as root) so the host `kubectl` can always read the context it just fetched;
   a missing context or unreachable API fails immediately, with a stderr-visible
   kubectl dump. On a node failure it dumps that kubectl dump, the emulator
   logs and the Docker container list (the k3s node included) to `.generated/`
   so the uploaded artifacts show what the substrate did.
- **The check** — `bootstrap/smoke-eks.sh` (driven by `make smoke
  COMPONENT=eks`): asserts a `Ready` node on context `floci-eks`, pushes the
  pinned `AWS_CLI_IMAGE` to `${account}.dkr.ecr.${region}.localhost:4566` via
  `ecr get-login-password` + `docker login`, then runs an in-cluster `Job` that
  pulls the image through the node's ECR registry mirror and prints
  `EKS_ECR_PULL_OK`.
- **Full platform** — the EKS run boots the whole catalog by seeding the
  app-of-apps wiring host-side (`make bootstrap ENV=local`, which resolves the
  ArgoCD manifests' `repoURL`/`targetRevision` to the PR head via the `sed` seam),
  after which ArgoCD reconciles the **real app-of-apps** (ApplicationSet
  `platform-local` → the dedicated `kong-local` + `linkerd-local`), gates every
  platform Application (`<name>-local`, Kong and Linkerd included), seeds Vault
  (it is born sealed, so
  it can only report `Healthy` once `seed-vault.sh` ran), then gates the whole
  catalog on `Synced/Healthy`, runs the touched component smoke(s), the EKS check
  and the endpoint check. It is the most complete test in the repo: the same
  GitOps path `dev`/`qa`/`prod` use, on an EKS-shaped cluster.
- **Wiring** — `smoke-ci.sh` has a single path: `make eks-up` boots the EKS
  substrate, `make bootstrap ENV=local` seeds the platform `ApplicationSet` and
  the dedicated `kong-local`/`linkerd-local` from the PR head and applies the
  catalog, the
  catalog is gated `Synced` → Vault seeded → `Synced/Healthy`, and the touched
  component smoke(s), the EKS check and the endpoint check run against it. The
  runner seeds the wiring host-side because it cannot reach the EKS node's pod
  network (the emulator publishes only its own port), so no git serve is
  involved. `--no-cluster` reuses an existing bootstrapped
  cluster; the run always shares the one required `Smoke` check.
- **Pins** — Floci, the AWS CLI and the EKS/ECR coordinates (`FLOCI_EKS_*`,
  `FLOCI_AWS_*`) are pinned in `bootstrap/versions.sh`, covered by the pin guards
  ([security.md](security.md)), and overridable via `.env`.

### Linkerd mesh smoke (data plane)

`make smoke COMPONENT=linkerd` (`bootstrap/smoke-linkerd.sh`) proves the mesh
carries traffic, not just that the control plane is up:

- **Preflight (clock/TTL)** — before the rollout gate, it port-forwards each
  control-plane proxy's admin endpoint (`:4191`) and reads
  `identity_cert_expiration_timestamp_seconds`. A leaf with less than 1h left
  fails with a pointer to the emulator clock. The controller containers are
  distroless, so the read is a host-side port-forward, not an `exec`.
- **Injected workload** — a throwaway namespace (`linkerd-smoke`, deleted on
  exit; `LINKERD_SMOKE_KEEP=1` keeps it for debugging) is annotated
  `linkerd.io/inject: enabled`; a pinned
  `nginx-unprivileged` server (`:8080`) and a `curlimages/curl` Job exercise the
  data plane. The smoke asserts both pods carry the `linkerd-proxy` container
  and the `linkerd.io/created-by=linkerd/proxy-injector` /
  `linkerd.io/proxy-version` annotations — a silently skipped injection
  (`failurePolicy: Ignore`) is a hard failure.
- **Real request** — the client `curl`s the server's Service through the mesh
  (200 + a known body), checks `/ready` and its own live identity leaf, and both
  proxies must report `response_total{classification="success"}` for `direction`
  `outbound` and `inbound`. When the proxy exposes a `tls` label it is asserted
  `tls="true"`; otherwise mTLS is proven by both proxies holding live leaves
  and the request traversing both.
- **Clock/TTL caveat** — the emulated EKS node's clock can advance past the
  chart's 24h identity leaf lifetime, leaving new proxies with `Expired`
  certificates (old pods keep serving, so ArgoCD still says `Healthy`). The
  `local` overlay raises `identity.issuer.issuanceLifetime` to `168h0m0s`;
  dev/qa/prod keep the default. CI always boots a fresh cluster (<24h), so it is
  not affected. If it happens on a long-lived local cluster, delete the linkerd
  pods to re-issue leaves.
- **Pins** — `LINKERD_SMOKE_SERVER_IMAGE` and `LINKERD_SMOKE_CLIENT_IMAGE` live
  in `bootstrap/versions.sh`, covered by the pin guards.

### Environment profile: `local` (not `qa`)

The smoke runs the **`local`** profile (1 replica, auto-sync + prune), never
`qa`. This is a deliberate decision on resources and security:

| Criterion | `local` (1 replica, auto+prune) | `qa` (3 replicas, PDB, anti-affinity, no-prune) |
| --- | --- | --- |
| Fits a CI runner (2 vCPU / 7 GB node) | Yes | No — HA (3 replicas + anti-affinity) overflows it / OOM |
| Converges within the wait timeout (up to 15 min) | Yes | Slower; risks false-fail timeouts |
| Actually exercises HA / anti-affinity | — | **No**: a 1-node cluster cannot; validating "HA" there is false confidence |
| Reproducible between PRs | Prune → clean, identical state each run | `no-prune` → residual state accumulates |
| What it proves | "applies and works (local)" | "resists HA" — that is `promote-test`'s job, on real envs |

- **Security**: the smoke is an **ephemeral, isolated** cluster that is
  torn down after every run; it never touches `qa`/`prod`. The real security
  boundary is the runner's minimal scope (`permissions: contents: read`, no
  injected real kubeconfigs/secrets) — not the replica count.
- **Promotion stays separate**: the jump to real HA (`dev`/`qa`/`prod`) is
  gated by `promote-test` ([workflow.md](workflow.md)), which loads the target
  env overlay on the local Floci emulated EKS substrate. The smoke validates correctness;
  `promote-test` validates the env overlay against a real protectable surface.
- **Merge gate**: the `Smoke` check is a **required branch-protection check on
  `main`** (branch protection must include `Smoke` in the required status
  checks). A PR that touches a platform component must pass the smoke to merge;
  docs-only PRs (like the release-please PR, which touches only
  `CHANGELOG.md`/`manifest`) resolve to no component and the smoke step skips
  cleanly, so they are not blocked by a cluster boot. Manual one-off smokes run
  via `workflow_dispatch`.

### Release gate

`release-gate.yml` is a thin wrapper over the org shared
`shared-qa-lock-check.yml` and runs on every PR, holding a single fact: **a
release-please PR against the default branch must merge before any human
PR**. While one is open, human
PRs keep a failing `release-gate` check (`::error` and non-zero exit) and
cannot merge; the release PR is excluded (the shared gate detects the
release-please PR by its `chore(...release...)` title, which only release-please
produces), so it is never blocked. Because the
check is registered as a required context on `main`, the block is enforced by
branch protection, not by policy. (The previous local gate keyed on the
reserved head branch `release-please--branches--main`; the shared template keys
on the title instead — same effect, one release PR at a time.)

The reusable workflow is called unconditionally, and that is load-bearing. The
required context is the **nested** check run `release-gate / release-gate`
(caller job / callee job), which GitHub only creates if the reusable is
actually invoked. A job-level `if` that exempts bot-authored PRs does not
"skip the gate for bots": it skips the whole call, the nested run is never
created, and the required context has no check run to wait for — so every
Dependabot or release-please PR hangs on `Expected — waiting for status to be
reported`. A skipped *job* reports conclusion `skipped`; a job that never runs
reports nothing, and nothing never satisfies a required context. That
exemption was tried and removed.

Bot PRs are therefore gated like any other PR: they report the check
immediately and pass, unless a release PR is actually open. That is a bounded
wait rather than a deadlock — the gate turns green as soon as the release PR
merges, and Dependabot re-runs it on the next rebase. A true bot exemption
requires the condition to live in the *callee*, as an input on the shared
template, so the nested run is still reported (as `skipped`); that is tracked in
`sca-templates/CI-CD-Templates` and deliberately not emulated here.
`workflow_dispatch` keeps the gate manually verifiable.

## Required checks

`main` is enforced by the active **`main-protected` ruleset** (required
status checks + one human review + DCO). Ruleset contexts match the
**check-run names** CI reports on every PR head — when a workflow delegates to
a reusable template, GitHub reports its jobs as `<caller> / <scan>`, so the
contexts below are the nested names:

1. `Validate / Markdown`, `Validate / YAML and Shell` — the shared-hygiene
   checks called from `validate.yml` (required on every PR).
2. `Kubernetes and Helm` — the local manifest and Helm lint in `validate.yml`
   (required on every PR).
3. `Security / Secrets (gitleaks)` — gitleaks (via the shared template) —
   required on every PR; blocks on findings.
4. `Security / IaC posture (checkov)` and `Guard policies` — checkov (via the
   shared template) and the local pin guards.
5. `CodeQL / Analyze (actions)` — required once stable.
6. `release-gate / release-gate` — required on every PR (fails while a release
   PR is open; the release PR itself is exempt, because the shared gate
   detects it by title). Bot-authored PRs are gated like humans and report the
   check immediately.
7. Human review — always the last gate for "turns green".

`Security / Dependency Vulnerabilities (osv)` runs the same scan but is **not**
a required context. A clear PR must satisfy Markdown + YAML + shell + workflow
lint, kube-linter, gitleaks, checkov and osv-scanner before merge. If a caller
job or a template job is renamed, the `main-protected` ruleset contexts must be
updated to the new reported check-run names.

## Local parity

Everything CI runs statically can be reproduced locally:

```bash
make validate-static     # markdownlint, yamllint, YAML parse, bash -n
make validate            # static + live cluster checks (needs eks-up)
```

yamllint runs locally only if installed; CI always runs it.
