<div align="center">

# 🐆 Panther Minor

### Self-hosted AI workstation stack for [AMD](https://www.amd.com/en.html)

![Platform](https://img.shields.io/badge/Platform-Ubuntu%2026.04%20LTS%2B-0A84FF)
![GPU](https://img.shields.io/badge/GPU-AMD%20RDNA%204-E01F27)
![Inference](https://img.shields.io/badge/Inference-llama.cpp%20%2B%20stable--diffusion.cpp-4CAF50)
![Monitoring](https://img.shields.io/badge/Monitoring-Grafana%20%2B%20Prometheus-F46800)

A reproducible, self-hosted AI cluster tuned for **AMD Ryzen + RDNA 4** systems: **llama.cpp**,
**stable-diffusion.cpp**, **Open WebUI**, **Prometheus** and **Grafana**, with **Tailscale access**, **hardened SSH**
and **smart GPU usage management**.

**[📚 Documentation](docs/README.md)** · [Installation](docs/installation.md) · [Operations](docs/operations.md) ·
[CLI](docs/cli.md)

</div>

---

## ✨ Highlights

| Feature                     | What it gives you                                                                                             |
| --------------------------- | ------------------------------------------------------------------------------------------------------------- |
| **Local inference**         | OpenAI-compatible LLM API powered by [llama.cpp](https://github.com/ggml-org/llama.cpp)                       |
| **Local image generation**  | OpenAI-compatible image API powered by [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) |
| **Built-in monitoring**     | Prometheus, Grafana, and exporters for host + GPU visibility                                                  |
| **GPU power & VRAM saving** | Idle model unloading and serialized large-model switching                                                     |
| **Secure remote access**    | Tailscale-scoped ports, key-only SSH on port `2222`, firewall, and fail2ban                                   |
| **Reproducible setup**      | One CLI-driven installation flow for the whole workstation                                                    |

> [!IMPORTANT]
> Panther Minor is a **single-tenant** system for one trusted user and workload. It is not suitable for multi-user or
> untrusted environments.

## 🚀 Quick start

**Requires** Ubuntu Server 26.04 LTS+, 2x AMD RDNA 4 GPUs, a Tailscale account and a domain — see
[Installation](docs/installation.md#-prerequisites) for hardware and BIOS settings.

```bash
# 1. Clone a release and prepare the host (reboot afterwards)
git clone https://github.com/rozsival/panther-minor.git
cd panther-minor
git checkout v12.0.1
sudo ./bin/panther-minor setup
sudo reboot

# 2. Reconnect on port 2222, join Tailscale, scope ports to it
ssh -p 2222 <user>@<server-ip>
sudo tailscale up
sudo ./bin/panther-minor setup env

# 3. Issue TLS certificates and enable renewal
./bin/panther-minor proxy certbot --domain <domain> --challenge-record _acme-challenge
./bin/panther-minor proxy setup-cron

# 4. Download the default models and start the cluster
./bin/panther-minor models llm download Qwen3.8-27B
./bin/panther-minor models llm download Qwen3.5-2B
./bin/panther-minor models llm download Qwen3-Embedding-0.6B
./bin/panther-minor cluster start
```

Then open `https://<domain>:8080` (Open WebUI) or point an OpenAI client at `https://<domain>:8000/v1`.

> [!WARNING]
> After `setup`, SSH accepts **keys only on port 2222**. Keep your current session open until a second one connects.

## 📚 Documentation

Everything else — architecture, networking, models, GPU management, monitoring, coding harnesses, CLI and
development — lives in **[docs/](docs/README.md)**.

## 👤 Ownership

| Item       | Details                                                                                                 |
| ---------- | ------------------------------------------------------------------------------------------------------- |
| Maintainer | [@rozsival](https://github.com/rozsival) (see [`CODEOWNERS`](CODEOWNERS))                               |
| Issues     | [GitHub Issues](https://github.com/rozsival/panther-minor/issues)                                       |
| Companion  | [Panther Minor Controller](https://github.com/rozsival/panther-minor-controller) — remote power control |
| License    | [MIT](LICENSE)                                                                                          |
