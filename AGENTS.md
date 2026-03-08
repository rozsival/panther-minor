# 🤖 Panther Minor - Agent Context

This file provides essential context, architecture details, and guidelines for AI agents assisting with this repository.

## 📖 Project Overview

**Panther Minor** is a local AI Workstation Setup specifically designed and optimized to serve Large Language Models (LLMs) on AMD RDNA 4 hardware (e.g., Radeon AI PRO).

## 🛠️ Tech Stack & Architecture

- **Host/OS**: Ubuntu Server, specifically configured with protective firewall rules, secure SSH, and Tailscale for access.
- **Hardware**: AMD RDNA 4 GPUs. (Requires disabled iGPU and specific kernel parameters: `amdgpu.mes=0 iommu=pt`). Host needs ROCm 6.3+.
- **Orchestration**: Docker Compose (see `docker-compose.yml`).
- **Core Services**:
  - **Ollama**: Handles LLM inference using `ollama/ollama:rocm`. Exposed via an OpenAI-compatible API at `http://localhost:8000/v1`. Currently the preferred engine over vLLM for RDNA 4 stability.
  - **Open WebUI**: The primary chat interface running on port `8080`.
- **Monitoring Stack**:
  - **Prometheus** (`monitoring/prometheus.yml`) routing metrics from target services.
  - **Grafana** (Dashboards in `monitoring/grafana/dashboards/system.json`).
  - **Exporters**: Runs `node-exporter` (host metrics) and `device-metrics-exporter` (AMD GPU metrics).

## ⚠️ Important Development Notes

1. **Inference Engine**: We migrated from vLLM to Ollama due to stability/performance on RDNA 4. Do not revert to vLLM.
2. **Metrics**: Grafana and Prometheus have been configured to scrape and display Ollama's native Prometheus metrics (`ollama_prompt_eval_count_total`, `ollama_eval_count_total`, etc.). Avoid referencing old vLLM metrics.
3. **Auto-Pulling**: The stack includes a custom `ollama-puller` container to automatically fetch the configured model (default: `qwen2.5-coder:14b-instruct`) on startup.

## Git commit messages

Strictly use Conventional Commits v1.0.0 format for commit messages. Prefer "lower case" over "Sentence case". Avoid final punctuation.
