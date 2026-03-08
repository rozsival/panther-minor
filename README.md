# 🐆 Panther Minor

The AI Workstation Setup

## Pre-requisites

- Ubuntu Server 25.10 or newer
- Server created with name `panther-minor`
- User `vit` created during installation
- Server pre-installed with OpenSSH
- Docker and Docker Compose [installed](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)

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

> [!IMPORTANT]
> You need to be connected to Tailscale to access the server every time.

## AMD GPU Kernel with ROCm

> [!WARNING]
> You should disable the iGPU in the BIOS for ROCm to work properly. Ensure you have a DisplayPort connected to the dedicated GPU.

### Kernel Parameters (RDNA 4)

1. Edit GRUB: `sudo nano /etc/default/grub`
2. Add `amdgpu.mes=1 iommu=pt` to `GRUB_CMDLINE_LINUX_DEFAULT`.
3. Update and reboot:

   ```bash
   sudo update-grub
   sudo reboot
   ```

### Install ROCm

Follow the instructions at [AMD Docs](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/install-methods/package-manager/package-manager-ubuntu.html) to install ROCm.

## Ollama Cluster

Runs a local LLM across both GPUs with an OpenAI-compatible API, plus a monitoring stack.

### Configuration

Copy the example env file and [pick a model](https://ollama.com/search):

```bash
cp .env.example .env
```

### Start

```bash
make start
```

The first start will pull the model from the Ollama registry via the auto-puller service. Watch progress with:

```bash
make ollama-puller-logs
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
    "model": "qwen2.5-coder:14b-instruct",
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

The **Panther Minor** dashboard in Grafana shows GPU utilisation, VRAM, temperature, power draw (both GPUs), CPU/RAM usage, and Ollama request metrics.

> The AMD GPU exporter metric names shown in the dashboard are based on `rocm/device-metrics-exporter`. If panels show "No data", browse to `http://panther-minor:9090/graph` and explore `amd_*` metrics to find the exact names for your GPU model, then update the dashboard queries accordingly.

### Stop

```bash
make stop
```

Model weights are cached in the `ollama-data` Docker volume and will not be re-downloaded on subsequent starts.
