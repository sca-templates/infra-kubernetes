# Onboarding a New Service

How to add a new microservice to the platform using the shipped template, and
the gates it must pass. This doubles as the per-component **add checklist**:
any catalog component (Phases 1–18) follows the same skeleton — chart or CRs,
env overlays, `ExternalSecret` where needed, one commit per component.

## 1. Scaffold the chart from the template

`charts/service-template/` is the starter Helm chart. Copy it to
`infrastructure/<service>/` and rename:

```bash
cp -r charts/service-template infrastructure/<service>
```

Customize:

- `Chart.yaml` — name/version (no floating tags; pin the upstream image by
  version in `values.yaml`).
- `templates/deployment.yaml`, `service.yaml`, `configmap.yaml` — the real
  workload.
- Delete the templates the service does not use (`ingress.yaml`, `hpa.yaml`,
  `pdb.yaml`, `servicemonitor.yaml`, `externalsecret.yaml` are optional).
- `values.schema.json` — keep the schema in sync with the values you ship.

The repo builds **no images**: `image.repository` + `image.tag` point at an
official upstream release. `latest` fails in CI (pin guards) and is ruled out
by policy ([security.md](security.md)).

## 2. Register the component per environment

- Shared defaults and the chart reference: `infrastructure/<service>/` (Phase
  1 onward).
- Env-specific values: one `envs/<env>/<service>.yaml` per environment
  (`local`, `dev`, `qa`, `prod`) mirroring `values.yaml`.
- Registry: add the component name to `argocd/apps-<env>.yaml` generators, or
  as a dedicated `Application` for the special cases in
  [architecture.md](architecture.md) (Kong, postgres-app).

A promotion changes only `envs/<env>/` + `apps-<env>.yaml` in a separate PR
([workflow.md](workflow.md)).

## 3. Wire secrets (if any)

Follow the per-component secret flow in [secrets.md](secrets.md):

1. Add the path to the seed plan (`secret/<service>/<env>`).
2. One `ExternalSecret` → `ClusterSecretStore vault`.
3. Pods mount the projected `Secret`; the raw value never appears in the
   manifest.

## 4. Gates (per-component DoD)

Merge is allowed only when the component passes its road-gate:

- Chart renders and applies; app `Synced` + `Healthy`.
- Pods `Running` — no `CrashLoopBackOff`/`ImagePullBackOff` after 2+ min.
- `ExternalSecret` → `SecretSynced` where applicable.
- Functional smoke passes (Phase 8 uses "echo via NodePort 30080", Phase 10
  "`psql SELECT 1`", and so on — each phase's gate is in
  [status.md](status.md)).
- `make status` shows no new `Degraded`.
- One commit, human-reviewed. If it does not turn green: **roll back**, never
  `fix`-chain.

## 5. Onboarding → platform

- Expose it behind Kong (Phase 8) so it is not reachable out-of-band.
- Add its `ServiceMonitor` to the radar set (Phase 14 design,
  [observability-radar.md](observability-radar.md)).
- Back it up with a Velero schedule/namespace label (Phase 18).
- Update the component catalog table in `docs/architecture.md` and the
  road-gate in `docs/status.md` in the same commit that lands the service:
  the docs are the source of truth and are updated as components land.
