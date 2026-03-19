# AGENTS.md

This file provides guidance to AI assistants (Claude, Gemini, Copilot, OpenCode etc.) when working with code in this
repository.

## Project Overview

Panther Minor is a self-hosted AI workstation setup designed for running LLMs and AI services on
AMD hardware with ROCm support. It includes configurations for llama.cpp, Open WebUI, Prometheus, Grafana, and exporters
for monitoring GPU and node performance.

## Stack

- **Host**: Ubuntu 25.10+, ROCm 7, kernel params `amdgpu.mes=1 iommu=pt`
- **Services**: llama.cpp, Open WebUI, Prometheus, Grafana, GPU/node exporters
- **Network**: See PORTS.md. SSH on 2222, services on 3000/5000/8000/8080/9090
- **Config**: `.env` (from `.env.example`), `docker-compose.yml`, `bin/src/*`

## Critical Rules

1. **Code Style** – follow the rules in `.editorconfig` and `biome.json` for consistent formatting and linting
2. **Use llama.cpp only** — custom build in `llama-cpp/Dockerfile` with ROCm v7 and `gfx1201` support
3. **Package manager** — `apt` only (never `apt-get`)
4. **Commits** — Conventional Commits v1.0.0, lowercase, no final punctuation, 100 chars max

## Key Files

- `README.md` — setup instructions, architecture overview, service access details
- `PORTS.md` — detailed port configuration and access methods
- `bin/README.md` — overview of the `./bin/cli` command tree and authoring workflow
- `models/README.md` — overview for custom `llama.cpp` models with `./bin/cli models *` usage and `preset.ini` config
- `docker-compose.yml` — service definitions with health checks
- `monitoring/prometheus.yml` — node and GPU exporter targets for Prometheus
- `monitoring/grafana/dashboards/gpu.json` — Grafana dashboard for GPU metrics
