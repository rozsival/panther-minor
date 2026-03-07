# 🐆 Panther Minor

The AI Workstation Setup

## Pre-requisites

- Ubuntu Server 25.10 or newer
- Server created with name `panther-minor`
- User `vit` created during installation
- Server pre-installed with OpenSSH

## Setup

Clone the repository and run the setup script:

```bash
git clone https://github.com/rozsival/panther-minor.git
sudo bash panther-minor/setup.sh
```

The script will automatically configure:

- **SSH** — hardens `/etc/ssh/sshd_config` (port 2222, key-only auth, restricted users)
- **UFW** — sets up the firewall (ports 2222, 80, 443)
- **fail2ban** — installs and configures brute-force protection

> [!NOTE]
> After the script completes, SSH will be available on **port 2222** only.
> Reconnect with: `ssh -p 2222 vit@<server-ip>`

## Tailscale

Follow the instructions at [Tailscale Docs](https://tailscale.com/docs/install/ubuntu/ubuntu-2510) to add the server to Tailscale.

Connect to the server via Tailscale:

```bash
ssh -p 2222 vit@panther-minor
```

> [!NOTE]
> You need to be connected to Tailscale to access the server every time.

## AMD GPU Kernel with ROCm

> [!WARNING]
> You should disable the iGPU in the BIOS for ROCm to work properly. Ensure you have a DisplayPort connected to the dedicated GPU.

Follow the instructions at [AMD Docs](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/install-methods/package-manager/package-manager-ubuntu.html) to install ROCm.

## vLLM Cluster

Runs a local LLM across both GPUs with an OpenAI-compatible API, plus a monitoring stack.

### Prerequisites

- Docker and Docker Compose [installed](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)
- ROCm installed (see section above)
- The repo already cloned on the server

### Configuration

Copy the example env file and pick a model:

```bash
cp .env.example .env
```

> [!WARNING]
> Make sure you set the `HF_TOKEN` before starting everything up.

The default is `Qwen/Qwen2.5-Coder-32B-Instruct` — a strong coding model that fits across both GPUs. Edit `MODEL` in `.env` to switch to any other option listed in the file (see comments for full list of Qwen chat and coder variants).

### Start

```bash
docker compose up -d
```

The first start will download the model from Hugging Face (~65 GB for Coder-32B). Watch progress with:

```bash
docker compose logs -f vllm
```

### API

The OpenAI-compatible API is available at `http://panther-minor:8000/v1`.

List loaded models:

```bash
curl http://panther-minor:8000/v1/models
```

Chat completion:

```bash
curl http://panther-minor:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-14B",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

Connect any OpenAI-compatible client (Continue.dev, LiteLLM, etc.) to `http://panther-minor:8000/v1` with any API key (auth is not enabled).

### Browser Tools

| Service               | URL                         | Credentials       |
| --------------------- | --------------------------- | ----------------- |
| **Open WebUI** (chat) | `http://panther-minor:8080` | no login required |
| Grafana (monitoring)  | `http://panther-minor:3000` | `admin` / `admin` |
| Prometheus            | `http://panther-minor:9090` | —                 |

The **Panther Minor** dashboard in Grafana shows GPU utilisation, VRAM, temperature, power draw (both GPUs), CPU/RAM usage, and vLLM request metrics.

> [!NOTE]
> The AMD GPU exporter metric names shown in the dashboard are based on `rocm/device-metrics-exporter`. If panels show "No data", browse to `http://panther-minor:9090/graph` and explore `amd_*` metrics to find the exact names for your GPU model, then update the dashboard queries accordingly.

### Stop

```bash
docker compose down
```

Model weights are cached in the `huggingface-cache` Docker volume and will not be re-downloaded on subsequent starts.
