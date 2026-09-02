---
description: Show cluster, ArgoCD applications and pod health overview, plus the current roadmap state.
agent: build
---

# Status

Run `make status` from the repo root and report the result. Every ArgoCD
Application should be `Synced`/`Healthy` and every pod `Running`/`Completed`.
Also point the user at `docs/status.md` — the roadmap and known-limitations
table are the source of truth for what is deployed and what is next. If
something is off, isolate it with the guidance in the `platform-lifecycle`
skill (OutOfSync apps, ExternalSecret errors, CrashLoopBackOff after wave
bumps) before changing anything.
