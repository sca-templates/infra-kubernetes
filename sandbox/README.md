# Sandbox deployment pipeline (EKS-parity target)

Step-by-step validation of the GitHub Actions -> self-hosted runner -> kind
pipeline before any cloud spend: the same `deploy.yml` drives either a local
`kind` cluster or EKS purely by swapping repo-level variables.

| Variable | local | eks |
| --- | --- | --- |
| `DEPLOY_ENV` | `local` | `eks` |
| `KUBE_CONTEXT` | `kind-cicd-test` | `<eks-cluster>` |
| `DEPLOY_NAMESPACE` | `sca-sandbox` | `sca-sandbox` |

`deploy.yml` renders and installs the `charts/service-template` chart with the
overlay selected by `DEPLOY_ENV`:

- `deploy/values-local.yaml` — minimal, non-root footprint for the kind sandbox.
- `deploy/values-eks.yaml` — HA-shaped values for the cloud target (guarded by
  `DEPLOY_ENV == 'eks'`; never applied locally).

Cloud-only steps (image build+push, EKS promote) run only when
`DEPLOY_ENV=eks`; locally the entire local path is exercised end-to-end.

This is the experiment harness, not the GitOps surface: the platform keeps
deploying through ArgoCD (`argocd/`, `envs/`, `infrastructure/`).
