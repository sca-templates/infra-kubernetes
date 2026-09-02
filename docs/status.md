# Status: Current State and Known Gaps

An honest picture of the platform today: what is deployed where, what is being
worked on, what is intentionally absent. Anything not listed here is either in
the component catalog ([architecture.md](architecture.md)) or does not exist.

The **delivery plan** (the 18 phases, their gates and the Work Log) now lives
in [roadmap.md](roadmap.md) and is tracked on the GitHub Projects board,
Milestones and Issues.

## Current state

**Phase 0.1 — scaffold + knowledge base only.** Nothing beyond ArgoCD is
deployed. Phase 0.0 delivered the empty scaffold (Makefile, `bootstrap/`,
`argocd/` with `{{GIT_REPO_URL}}` placeholders, the four CI workflows, the
service template, this docs set) and brought the local `kind` cluster up with
ArgoCD. Phase 0.1 adds this knowledge base, which is **the source of truth**
for everything deployed in Phases 1–18 and beyond.

| Fact | Value |
| --- | --- |
| Repository | `infra-kubernetes` (local; published to GitHub before Phase 1 — a live `GIT_REPO_URL` is a Phase 1 gate) |
| Deployed components | ArgoCD only (bootstrap) |
| `platform-root-local` | present, `OutOfSync` (accepted — no live repo yet) |
| `platform-local` ApplicationSet | present, empty `elements: []` (0 generated apps) |
| Observability / smoke CI | cluster smoke `pr-cluster.yml` not shipped yet — **returns at Phase 1** (profile `local`; see [ci-cd.md](ci-cd.md)) |
| dev / qa / prod clusters | pending (provisioned by terraform/ansible, outside this repo) |

## Known accepted limitations

| # | Limitation | Current behavior | To close |
| --- | --- | --- | --- |
| 1 | **Root app OutOfSync** | `platform-root-local` shows `OutOfSync`; auto-sync disabled live because the `GIT_REPO_URL` placeholder is a public repo with legacy content | Publish this repo, swap `GIT_REPO_URL`, re-enable file-state (auto + prune) |
| 2 | **Cluster smoke CI absent (until Phase 1)** | `pr-cluster.yml` is not shipped yet — the merge gate is static validation + human review | Returns at **Phase 1** with cert-manager: selective smoke of the touched component on an ephemeral `kind` cluster, profile `local` (1 replica, auto-sync + prune), no trim hacks, no self-heal disabling; informative until stable on 2–3 components (see [ci-cd.md](ci-cd.md)) |
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
