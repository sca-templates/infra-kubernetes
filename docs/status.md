# Status: Current State and Known Gaps

An honest picture of the platform today: what is deployed where, what is being
worked on, what is intentionally absent. Anything not listed here is either in
the component catalog ([architecture.md](architecture.md)) or does not exist.

The **delivery plan** (the 18 phases, their gates and the Work Log) now lives
in [roadmap.md](roadmap.md) and is tracked on the GitHub Projects board,
Milestones and Issues.

## Current state

**Phase 1 — cert-manager deployed.** Phase 0 delivered the scaffold (Makefile,
`bootstrap/`, `argocd/` with the app-of-apps pattern, the CI workflows, the
service template, this docs set) and brought the local `kind` cluster up with
ArgoCD. **Phase 1** lands the first real component, cert-manager, on the
`local` profile (fully-local: ArgoCD reconciles an in-cluster git serve instead
of GitHub) and ships the cluster smoke. See [ci-cd.md](ci-cd.md) for the smoke
design.

| Fact | Value |
| --- | --- |
| Repository | `infra-kubernetes` (local, fully-local git serve; published to GitHub before promotion) |
| Deployed components | ArgoCD (bootstrap), cert-manager (Phase 1) |
| `platform-root-local` | present, `Synced` against the local git serve (`main`) |
| `platform-local` ApplicationSet | present, one element (`cert-manager`, wave -20) |
| cert-manager app | `cert-manager-local` `Synced` + `Healthy`; `sca-ca` ClusterIssuer `Ready`; leaf Certificate smoke green |
| git-local-serve | in-cluster git daemon (`git://<node>:9418/sca-infra.git`) `Ready` |
| Observability / smoke CI | cluster smoke `pr-cluster.yml` **shipped** (Phase 1): selective on PRs + vigilance on `push: main`; informative until stable on 2–3 components (see [ci-cd.md](ci-cd.md)) |
| Security CI | checkov **baseline gate** active (Phase 1): `.github/checkov-baseline.json` documents the local-git-server pod findings; new IaC findings fail the PR; re-evaluated at Phase 18 (see [security.md](security.md)) |
| dev / qa / prod clusters | pending (provisioned by terraform/ansible, outside this repo) |

## Known accepted limitations

| # | Limitation | Current behavior | To close |
| --- | --- | --- | --- |
| 1 | **Fully-local git serve (not GitHub)** | Local ArgoCD reconciles the in-cluster git serve (`git://<node>:9418`), not the GitHub repo; the native GitHub `GIT_REPO_URL` remains the default in the files | Publish the repo and swap `GIT_REPO_URL` back to GitHub to exercise the real source-of-truth path |
| 2 | **Cluster smoke shipped but informative** | `pr-cluster.yml` ships as an **informative** check — it boots an ephemeral `kind` cluster, applies the touched component via its ArgoCD `Application` (profile `local`, 1 replica, auto-sync + prune), waits for convergence and runs the smoke, but does not block a merge; `bootstrap/smoke-ci.sh` owns the boot→apply→wait→run→diagnose→teardown cycle | Make it a required branch-protection check on `main` once stable on 2–3 components (a branch-protection change, not a code change — see [ci-cd.md](ci-cd.md)) |
| 3 | **dev / qa / prod clusters pending** | Not provisioned (terraform/ansible outside this repo) | Provision per env; promote via `promote-test` (see [workflow.md](workflow.md)) |
| 4 | **Nothing seeded in Vault** | Vault seed script ships (`bootstrap/seed-vault.sh`) but is never run — no Vault yet | Runs at Phase 2; short ESO `refreshInterval` in local prevents the previous wedge |
| 5 | **OpenSSF Best Practices badge — silver blocked** | All silver criteria are met except `contributors_unassociated` and `bus_factor` (≥2): the project has a single maintainer (`CODEOWNERS` = `@Santiago1010`) | Achieved once a second **unassociated** contributor joins and is reflected in `CODEOWNERS` + `.github/GOVERNANCE.md`; passing badge is already achievable (see [.github/GOVERNANCE.md](../.github/GOVERNANCE.md), [docs/ci-cd.md](ci-cd.md)) |
| 6 | **OpenSSF Best Practices badge — gold blocked** | Beyond the silver gaps, gold requires `two_person_review` (≥50% of changes reviewed by someone other than the author), which is unrealisable while there is a single maintainer; all other gold criteria are Met or N/A (see [.github/SECURITY.md](../.github/SECURITY.md) security review, SPDX + copyright headers per source file) | Unblocked together with silver once a second, **unassociated** reviewer/maintainer exists; `two_person_review` then requires an explicit second reviewer on gold PRs |

## Intentional exclusions

- **No Unleash, no KafkaConnect/Debezium, no kafka-ui, no linkerd-viz
  in-cluster.** They are deliberate scope cuts of the restart plan.
- **No Consul and no Consul-k8s in-cluster** (ADR-001): native Kubernetes DNS +
  Linkerd replace it.
- **No `latest` tags, no image builds**: infrastructure pins upstream
  releases; this repo builds nothing.

## Read this doc

- Before any change, check the [roadmap](roadmap.md) and the [deviations
  log](architecture.md#deviations-log): they are the normative record.
- `local` is the demo/CI substrate; treat everything it runs as the minimal
  but *complete* platform, not as a reduced copy.
