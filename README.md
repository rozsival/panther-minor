# 🐆 Panther Minor

The AI Workstation Setup

## Pre-requisites

- [Ubuntu Server](https://ubuntu.com/download/server) 25.10 or newer
- Server created with name `panther-minor`
- User `$USER` created during installation
- Server pre-installed with OpenSSH

## Setup

Clone the repository and run the setup script:

```bash
git clone https://github.com/rozsival/panther-minor.git
sudo bash panther-minor/setup.sh
```

The script will automatically configure:

- **Essential Packages** — `build-essential`, `jq`, `nvtop`, `llmfit`, etc
- **Docker** — installs Docker Engine and Docker Compose
- **Tailscale** — installs the Tailscale agent
- **SSH** — hardens `/etc/ssh/sshd_config` (port 2222, key-only auth, restricted users)
- **UFW** — sets up the firewall (ports 2222, 80, 443)
- **fail2ban** — installs and configures brute-force protection
- **AMD GPU & ROCm** — installs the latest kernel drivers and ROCm v7
- **Kernel Parameters** — configures GRUB with `amdgpu.mes=1 iommu=pt`
- **Starship** — sets up a modern shell prompt for the `$USER` user

> [!IMPORTANT]
> **Reboot is required** after the script completes to load the new kernel drivers and parameters.
> After reboot, SSH will be available on **port 2222** only.
> Connect with: `ssh -p 2222 <user>@<server-ip>`

## Tailscale

After the system setup and reboot, authenticate the server to
your [Tailscale network](https://login.tailscale.com/admin/):

```bash
sudo tailscale up
```

> [!IMPORTANT]
> Tailscale authentication requires browser, since the server is headless, it is highly recommended to run the above
> command on a local machine via SSH to the server.

Follow the link in your browser to complete the authentication. Once connected, you can access the server via its
Tailscale IP or hostname:

```bash
ssh -p 2222 <user>@panther-minor
```

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

### Browser Tools

| Service               | URL                         | Credentials       |
|-----------------------|-----------------------------|-------------------|
| **Open WebUI** (chat) | `http://panther-minor:8080` | no login required |
| Grafana (monitoring)  | `http://panther-minor:3000` | `admin` / `admin` |
| Prometheus            | `http://panther-minor:9090` | —                 |

The **Panther Minor** dashboard in Grafana shows GPU utilisation, VRAM, temperature, power draw, CPU/RAM usage, and
Ollama request metrics.

### Stop

```bash
make stop
```
