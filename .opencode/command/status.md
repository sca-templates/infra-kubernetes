---
description: Show cluster, ArgoCD applications and pod health overview, plus the current state and roadmap.
agent: build
---

# Status

Run `make status` from the repo root and report the result. Every ArgoCD
Application should be `Synced`/`Healthy` and every pod `Running`/`Completed`.
Also point the user at `docs/status.md` (current state and known limitations)
and `docs/roadmap.md` (the delivery plan). If
something is off, isolate it with the guidance in the `platform-lifecycle`
skill (OutOfSync apps, ExternalSecret errors, CrashLoopBackOff after wave
bumps) before changing anything.
