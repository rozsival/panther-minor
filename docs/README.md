# 📚 Panther Minor Documentation

> Entry point to the Panther Minor documentation. Each page covers **one domain**, opens with a one-paragraph
> summary, links its related pages, and ends with an FAQ where one is useful.

New here? Start with [Installation](installation.md), then [Operations](operations.md). The project overview and
quick start live in the [root README](../README.md).

---

## 🗂️ Document index

| Document                                | Read when you want to…                               | Key topics                                                                    |
| --------------------------------------- | ---------------------------------------------------- | ----------------------------------------------------------------------------- |
| [Architecture](architecture.md)         | Understand how the services fit together             | Service map, request flow, single-tenant model, repository layout             |
| [Installation](installation.md)         | Prepare hardware and install the stack on a server   | Hardware, BIOS, OS, `setup` steps, Tailscale, SSL certificates                |
| [Networking & security](networking.md)  | Reach services securely, understand published ports  | `BIND_ADDR`, published ports, UFW, access patterns                            |
| [Operations](operations.md)             | Configure, start, stop, update or extend the cluster | `.env` reference, cluster lifecycle, logs, updates, overrides, remote control |
| [Models](models.md)                     | See which models exist and manage their weights      | LLM and text-to-image catalogs, shared weight cache, download/remove/prune    |
| [LLM serving](llm.md)                   | Serve, tune, benchmark or switch reasoning on LLMs   | Presets, weight placement, benchmarking, speculative decoding, reasoning      |
| [Image generation](image-generation.md) | Generate images and share GPUs with the LLMs         | `sd-server`, model switching, GPU assignment, recommended workflows           |
| [GPU power & VRAM](gpu-management.md)   | Understand idle unloading and large-model switching  | Idle unloading, large-model arbitration, image-generation VRAM                |
| [Monitoring](monitoring.md)             | Read dashboards and metrics                          | Prometheus targets, Grafana dashboards, exporter metrics                      |
| [Coding harnesses](harnesses.md)        | Connect a coding agent (OMP, Pi, OpenCode)           | Presets, image formats, thinking and effort control                           |
| [CLI reference](cli.md)                 | Look up a `./bin/panther-minor` command              | Command tree, flags, completions, maintainer workflow                         |
| [Development](development.md)           | Contribute, run checks or cut a release              | Toolchain, checks, tests, commit rules, releases, agent skills                |

## 🛤️ Reading paths

### First installation

1. [Installation](installation.md) — hardware, BIOS, `setup`, Tailscale, SSL
2. [Networking & security](networking.md) — why `BIND_ADDR` must be set before the cluster starts
3. [Models](models.md) — download at least the default chat, task and embedding models
4. [Operations](operations.md) — start the cluster

### Daily use

- [LLM serving](llm.md) and [Image generation](image-generation.md) for model behavior
- [GPU power & VRAM](gpu-management.md) when VRAM is tight
- [Monitoring](monitoring.md) to confirm what the GPUs are doing

### Maintainers

- [Development](development.md) for checks, commit rules and releases
- [CLI reference](cli.md) before touching `cli/*`
- [Architecture](architecture.md) for the repository layout

## ✍️ Documentation conventions

| Rule            | Detail                                                                                                     |
| --------------- | ---------------------------------------------------------------------------------------------------------- |
| Location        | All user and maintainer docs live in `docs/`, one domain per file, kebab-case names                        |
| Page shape      | `# Title` → summary quote → **Related** line → sections → `## ❓ FAQ` (when useful)                        |
| Source of truth | Config files (`.env.example`, `llama-cpp/preset.ini`, `*.config.json`) win; docs explain them              |
| Agent context   | `AGENTS.md`, `.github/copilot-instructions.md` and `.agents/skills/*/SKILL.md` stay where their tools look |
| Formatting      | Prettier (`printWidth: 120`) via `pnpm run fix`; GitHub-flavored Markdown with alerts and Mermaid          |
| Versions        | Only the root README carries the release tag (`git checkout vX.Y.Z`); the `release` skill bumps it         |
