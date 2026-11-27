<div align="center">

# 🐆 Panther Minor

### Self-hosted AI workstation stack for [AMD](https://www.amd.com/en.html)

![Platform](https://img.shields.io/badge/Platform-Ubuntu%2026.04%20LTS%2B-0A84FF)
![GPU](https://img.shields.io/badge/GPU-AMD%20RDNA%204-E01F27)
![Inference](https://img.shields.io/badge/Inference-llama.cpp%20%2B%20stable--diffusion.cpp-4CAF50)
![Monitoring](https://img.shields.io/badge/Monitoring-Grafana%20%2B%20Prometheus-F46800)

A reproducible, self-hosted AI cluster tuned for **AMD Ryzen + RDNA 4** systems: **llama.cpp**,
**stable-diffusion.cpp**, **Open WebUI**, **Prometheus** and **Grafana**, with **Tailscale access** and **smart GPU
usage management**. The host underneath is yours: [Pantheon](https://github.com/rozsival/pantheon) is the recommended
baseline, and any Ubuntu 26.04+ server with Docker works.

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
| **Tailnet-only access**     | One Tailscale sidecar node with automatic TLS; no service port published beyond the host's loopback           |
| **Prerequisite checks**     | `setup` verifies the host (Ubuntu, Docker) first, then installs only the GPU stack and what the CLI needs     |

> [!IMPORTANT]
> Panther Minor is a **single-tenant** system for one trusted user and workload. It is not suitable for multi-user or
> untrusted environments.

## 🚀 Quick start

**Requires** Ubuntu Server 26.04 LTS+ with Docker Engine and Compose, 2x AMD RDNA 4 GPUs and a Tailscale tailnet with
MagicDNS and HTTPS certificates enabled — see [Installation](docs/installation.md#-prerequisites) for hardware, BIOS
and [tailnet](docs/installation.md#-prepare-the-tailnet) settings. On a fresh server, set up the host with
[Pantheon](https://github.com/rozsival/pantheon) first: Docker, key-only SSH, a firewall and fail2ban.

```bash
# 1. Install the latest release into ~/panther-minor and prepare the host for the stack (reboot afterwards)
curl -fsSL https://github.com/rozsival/panther-minor/releases/latest/download/install.sh | bash
cd ~/panther-minor
sudo ./bin/panther-minor setup
sudo reboot

# 2. After the reboot, set the tailnet auth key (reusable, pre-approved, tagged tag:panther-minor;
#    signed with `tailscale lock sign` if you use Tailnet Lock, which is highly recommended)
cd ~/panther-minor
nano .env    # TS_AUTHKEY=tskey-auth-…

# 3. Download the default models and start the cluster
./bin/panther-minor models llm download Qwen3.8-27B
./bin/panther-minor models llm download Qwen3.5-2B
./bin/panther-minor models llm download Qwen3-Embedding-0.6B
./bin/panther-minor cluster start
```

Then open `https://panther-minor.<tailnet>.ts.net:8080` (Open WebUI) or point an OpenAI client at
`https://panther-minor.<tailnet>.ts.net:8000/v1`.

## 📚 Documentation

Everything else — architecture, networking, models, GPU management, monitoring, coding harnesses, CLI and
development — lives in **[docs/](docs/README.md)**.

## 👤 Ownership

| Item       | Details                                                                   |
| ---------- | ------------------------------------------------------------------------- |
| Maintainer | [@rozsival](https://github.com/rozsival) (see [`CODEOWNERS`](CODEOWNERS)) |
| Issues     | [GitHub Issues](https://github.com/rozsival/panther-minor/issues)         |
| Host       | [Pantheon](https://github.com/rozsival/pantheon) — the server baseline    |
| Companion  | [Janus](https://github.com/rozsival/janus) — remote power control         |
| License    | [MIT](LICENSE)                                                            |
