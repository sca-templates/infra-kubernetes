# infra-kubernetes Documentation

This is the complete knowledge base for the `sca` platform on Kubernetes. The
aim is that any human **or AI agent** can answer the *what*, the *how* and the
*why* of this repository without leaving it.

**These docs are the source of truth.** From Phase 1 onward, every phase prompt
reads `docs/` first, executes against the gates it defines, and updates
`status.md` and `architecture.md` as each component lands. Prefer the docs over
recollection — every claim here traces to a real file in the repo or to a
documented plan.

Reading order depends on who you are:

| Audience | Start here |
| --- | --- |
| New developer / junior | [README](../README.md) → `kubernetes-basics.md` → `workflow.md` → `glossary.md` |
| Someone new to Kubernetes | `kubernetes-basics.md` (concepts used by this repo, with official links) |
| Platform operator | `architecture.md` → `ci-cd.md` → `security.md` → `secrets.md` → `observability-radar.md` |
| Onboarding a service | `onboarding-new-service.md` |
| AI agent answering questions | `architecture.md` + `status.md` (both are indexes of truth) |
| Anyone checking current state | `status.md` |

## Prerequisite knowledge

`docs/` teaches the platform *and* the Kubernetes concepts it exercises
(`kubernetes-basics.md` + the glossary). It is **not** a substitute for the
official Kubernetes learning material — a reader entirely new to Kubernetes
should pair it with the linked official docs. Everything beyond that — how this
repository deploys, secret flow, CI/CD, onboarding — is fully self-contained
here.

## Document index

| File | Covers | Key source-of-truth files it references |
| --- | --- | --- |
| [kubernetes-basics.md](kubernetes-basics.md) | K8s concepts exercised by the repo: object model, operators, Helm, GitOps, networking, storage, identity | official kubernetes.io/helm.sh/argo-cd docs + `charts/service-template` |
| [architecture.md](architecture.md) | Layers, component catalog (with status + phase), sync-waves, namespaces, secret flow, environment model, deviations log | `argocd/*`, `envs/*`, `infrastructure/*` (from Phase 1) |
| [status.md](status.md) | Current state, known accepted limitations, intentional exclusions | live cluster + `make status` |
| [roadmap.md](roadmap.md) | The 18-phase delivery plan with gates, per-component DoD, and the Work Log; linked to GitHub Projects/Milestones/Issues | GitHub board; `docs/status.md` for what is deployed |
| [workflow.md](workflow.md) | GitOps model, change→deploy flow, per-env promotion with promote-test, escalation gate, troubleshooting | `argocd/*`, `Makefile` |
| [ci-cd.md](ci-cd.md) | What the four shipped GitHub Actions do; cluster-smoke plan (absent by design) | `.github/workflows/*.yml`, `Makefile` |
| [security.md](security.md) | Security controls wired into CI: gitleaks, checkov baseline, pinning guards, settings checklist, leaked-secret runbook | `.github/workflows/security.yml`, `codeql.yml`, `scorecard.yml` |
| [secrets.md](secrets.md) | Vault + ESO design, KV path inventory, seed script, short-refresh rationale, per-component secret flow | `bootstrap/seed-vault.sh` |
| [observability-radar.md](observability-radar.md) | Metrics pipeline and radar alerts as designed (planned until Phase 14) | roadmap in `roadmap.md` |
| [onboarding-new-service.md](onboarding-new-service.md) | Step-by-step to add a new microservice; doubles as the per-component add checklist | `charts/service-template`, `argocd/apps-<env>.yaml` |
| [glossary.md](glossary.md) | Every term and component name explained in one place | — |

## Conventions of this documentation

- **Reference-and-explain.** Every document points at the real files
  ("source of truth") and explains them with short excerpts. It deliberately
  does not copy entire manifests: duplication is what caused the historical
  drift between documentation and repository.
- **Truth over aspiration.** The documents describe what the repository
  contains today. Components that are planned but not deployed are explicitly
  marked `planned (Phase N)` in `architecture.md` and `status.md`, never
  silently listed as existing.
- **Docs move with their component.** The commit that lands a component also
  updates `architecture.md` (Status column, deviations log) and `status.md`
  (roadmap row). A doc that says one thing while the repo does another is a
  bug to fix in the same PR.
- **Runbooks** are imperative and safe to copy-paste.
- Content, commits and pull requests are in English (repository rule).
