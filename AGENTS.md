# AGENTS.md

This file provides guidance to AI assistants (Claude, Gemini, Copilot, OpenCode etc.) when working with code in this
repository.

## Project Overview

Panther Minor is a self-hosted AI workstation setup designed for running LLMs and AI services on
AMD hardware with ROCm support. It includes configurations for Ollama, Open WebUI, Prometheus, Grafana, and exporters
for monitoring GPU and node performance.

## Stack

- **Host**: Ubuntu 25.10+, ROCm 7, kernel params `amdgpu.mes=1 iommu=pt`
- **Services**: Ollama, Open WebUI, Prometheus, Grafana, GPU/node exporters
- **Network**: See PORTS.md. SSH on 2222, services on 3000/5000/8000/8080/9090
- **Config**: `.env` (from `.env.example`), `docker-compose.yml`, `scripts/*`

## Critical Rules

1. **Use Ollama only** — `ghcr.io/rjmalagon/ollama-linux-amd-apu:latest` with ROCm v7 and `gfx1201` support
   (waiting for https://github.com/ollama/ollama/pull/13000)
2. **Package manager** — `apt` only (never `apt-get`)
3. **Commits** — Conventional Commits v1.0.0, lowercase, no final punctuation
4. **Ollama config** — `OLLAMA_HOST=0.0.0.0:8000`, ROCm v7 lib, flash attention enabled
5. **Ports dynamic** — Scripts load from `.env` with fallback to defaults

## Key Files

- `README.md` — setup instructions, architecture overview, service access details
- `PORTS.md` — detailed port configuration and access methods
- `setup.sh` — orchestrates all `scripts/*.sh` to configure host system (kernel, ROCm, SSH, Git, shell)
- `scripts/common.sh` — shared config (SSH_PORT=2222, user, colors)
- `scripts/06-ufw.sh` — firewall (dynamically configures all service ports)
- `docker-compose.yml` — service definitions with health checks
- `monitoring/prometheus.yml` — scrapes Ollama metrics (`ollama_*`), node-exporter, GPU exporter
- `monitoring/grafana/dashboards/system.json` — pre-configured dashboard for system and Ollama metrics
