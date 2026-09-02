# infra-kubernetes

[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14423/badge)](https://www.bestpractices.dev/projects/14423)
[![Validate](https://github.com/sca-templates/infra-kubernetes/actions/workflows/validate.yml/badge.svg)](https://github.com/sca-templates/infra-kubernetes/actions/workflows/validate.yml)
[![Security](https://github.com/sca-templates/infra-kubernetes/actions/workflows/security.yml/badge.svg)](https://github.com/sca-templates/infra-kubernetes/actions/workflows/security.yml)
[![CodeQL](https://github.com/sca-templates/infra-kubernetes/actions/workflows/codeql.yml/badge.svg)](https://github.com/sca-templates/infra-kubernetes/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Portable GitOps source of truth for the `sca` infrastructure platform on
Kubernetes. ArgoCD reconciles this repository; **nothing is deployed by hand**.
This is a clean restart after the previous `infra-kubernetes` churned in
`fix(...)` commits — one component, one commit, one reviewed gate per phase.
Nothing beyond ArgoCD is deployed yet; the roadmap is in
[docs/roadmap.md](docs/roadmap.md).

## Quick Start (local)

```bash
make prereqs
make cluster-up
make bootstrap
make status
```

- `make prereqs` installs pinned, checksum-verified kubectl/helm/kind into
  `~/.local/bin` (idempotent).
- `make cluster-up` creates the pinned single-node `kind` cluster.
- `make bootstrap` installs ArgoCD and applies the environment root
  Application. `GIT_REPO_URL` comes from `.env` (see `.env.example`); a live
  URL is a Phase 1 requirement, until then the root app stays `OutOfSync` by
  design.
- From then on, changes land via git push → ArgoCD reconcile.

## Environments

| Environment | Profile | ArgoCD sync policy | Substrate |
| --- | --- | --- | --- |
| `local` | Full platform, one replica, minimal | Auto-sync + prune | `kind` |
| `dev` | Reduced HA | Auto-sync + prune | Kubernetes cluster |
| `qa` | HA, PDBs, anti-affinity | Auto-sync, **no prune** | Kubernetes cluster |
| `prod` | Full HA, real storage | **Manual sync** | Kubernetes cluster |

Select an environment with `ENV=local|dev|qa|prod`. Environment values live
under `envs/<environment>/` (Phase 1 onward); the per-environment component
registry is `argocd/apps-<env>.yaml`. Promotion between environments passes a
`promote-test` on local (see [docs/workflow.md](docs/workflow.md)).

## Platform Components

The catalog is **17 components** plus ArgoCD. `local` runs the full set;
`dev`/`qa`/`prod` run the operator/security core plus the gateway and Keycloak.

| Area | Components |
| --- | --- |
| Security and identity | cert-manager, Vault, External Secrets Operator, Keycloak |
| Edge and mesh | Kong, Linkerd control plane |
| Data | CloudNativePG (postgres-app, keycloak-db), Strimzi Kafka, Redis |
| Observability | kube-prometheus-stack, Loki, Tempo, Alloy |
| Delivery and resilience | MinIO (local-only), Velero |

MinIO is **local-only** (S3 stand-in for Velero); `dev`/`qa`/`prod` point
Velero at external S3 via Vault/ESO credentials. All images and charts are
pinned to explicit upstream versions — this repository builds no images.
Consul, Unleash, KafkaConnect/Debezium, kafka-ui and linkerd-viz are
intentionally excluded.

## Commands

| Command | Description |
| --- | --- |
| `make prereqs` | Install the pinned local CLI toolchain |
| `make cluster-up` | Create the local `kind` cluster |
| `make cluster-down` | Delete the local `kind` cluster |
| `make bootstrap` | Install ArgoCD and apply the environment root Application |
| `make status` | Show nodes, ArgoCD Applications and pod health |
| `make validate-static` | Run Markdown, YAML and shell validation without a cluster |
| `make validate` | Run static validation plus live cluster checks |
| `make port-forward APP=<name>` | Reach a platform UI/API locally (argocd, vault, keycloak, grafana, prometheus, …) |
| `make clean` | Remove local state (`.env`, `.secrets/`, generated artifacts) |

The Makefile is a thin wrapper: after bootstrap, deployments happen exclusively
via `git push` → ArgoCD.

## Documentation

This repository ships a complete knowledge base in
[docs/INDEX.md](docs/INDEX.md) — and from Phase 1 onward those docs are the
**source of truth**: architecture, the GitOps workflow, CI/CD, the Vault + ESO
secret strategy, the security posture, the radar alerts, service onboarding, a
glossary and an honest status page with the 18-phase
[roadmap](docs/roadmap.md). Readers new to
Kubernetes start with [docs/kubernetes-basics.md](docs/kubernetes-basics.md).
See [AGENTS.md](AGENTS.md) for the repository guide.

## Repository Rules

- Vault is the secrets source of truth; never commit `.env`, `.secrets/`,
  kubeconfigs, tokens or generated artifacts.
- One component = one commit, one PR, one review. A component that does not
  turn green rolls back — no `fix` chains, no ad-hoc `ignoreDifferences`/SSA
  patches, nothing deployed by hand after bootstrap.
- Sync-waves must preserve operator, datastore and consumer dependencies.
- Content, commits and pull requests are in English.
- No floating image tags or chart versions; pins are enforced by CI
  (`Security` guards). See [docs/security.md](docs/security.md).

## Agent tooling & MCP servers

This repository is preconfigured for AI coding agents (Claude Code, opencode,
Codex, VS Code) with shared **skills** and a repository **MCP server**.

### What is preconfigured

- **CodeGraph MCP** — a repo-local SQLite graph of this codebase's symbols and
  edges. Query it instead of grepping when you need to understand or locate
  code: `codegraph_explore` returns the relevant symbols' verbatim source plus
  the call paths between them in one call. Indexing is the **user's decision**:
  index with `codegraph init` in this directory (a new index is picked up
  live, no restart). Until a `.codegraph/` directory exists, CodeGraph is
  skipped and normal search tools are used.
- **Skills** — `.claude/skills/` is the shared location: `platform-lifecycle`
  (bootstrap, add-a-component checklist, health checks, troubleshooting and
  the armor rules) and `sca-docs` (documentation conventions). The same files
  are read by Claude Code, opencode (via `skills.paths` in `opencode.jsonc`),
  Codex and VS Code.
- **Slash commands** (opencode) — `.opencode/command/` (`bootstrap`,
  `status`, `validate`, `check`) wrap the Makefile targets for quick
  invocation inside the agent.
- **VSCode tasks** — `.vscode/tasks.json` exposes `platform: bootstrap /
  status / validate / validate-static`.

### How each agent discovers the MCP server

- **Claude Code** — reads `.mcp.json` at the repo root (stdio `codegraph
  serve --mcp`) and is granted the `mcp__codegraph__*` permission in
  `.claude/settings.json` (also enabled in the tool's MCP menu).
- **opencode** — reads the `mcp` block in `opencode.jsonc` (`type: "local"`,
  command `["codegraph","serve","--mcp"]`, `enabled: true`). Verify with
  `/mcp` inside opencode.
- **Cross-project servers** (e.g. GitHub) are **not** repo-scoped: they go in
  the **global** opencode config `~/.config/opencode/opencode.json` rather
  than the repo `opencode.jsonc`, so they are available in every project.

### Adding another MCP server

Every server has two config homes — declare it in the agent you use:

Claude Code, `.mcp.json` (repo-scoped; or the global
`~/.claude.json` for all projects) + an allow-rule in `.claude/settings.json`:

```jsonc
// .mcp.json
{
  "mcpServers": {
    "my-server": {
      "type": "stdio",
      "command": "/usr/local/bin/my-server",
      "args": ["--flag"]
    }
  }
}
```

```jsonc
// .claude/settings.json — allow the tool the server exposes
{
  "permissions": {
    "allow": ["mcp__my-server__*"]
  }
}
```

opencode, `opencode.jsonc` (repo) or `~/.config/opencode/opencode.json`
(global):

```jsonc
{
  "mcp": {
    "my-server": {
      "type": "local",            // "local" = stdio; "remote" = URL server
      "command": ["/usr/local/bin/my-server", "--flag"],
      "enabled": true
    }
  }
}
```

Verify with `/mcp` in opencode or the MCP menu in Claude Code; then test a
tool call from the agent.
