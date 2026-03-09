# 🐆 Panther Minor

The AI Workstation Setup

## Pre-requisites

### Hardware

- x870e motherboard with 2x PCIe Gen5 x16 slots
- AMD Ryzen 9 or newer (16+ cores recommended)
- 192 GB RAM DDR5
- 2x AMD Radeon Pro with RDNA 4 (32 GB VRAM each)
- 2 TB NVMe SSD

### BIOS

- Above 4G decoding enabled
- Resize BAR enabled
- iGPU disabled
- PCIe slots set to Gen5 and x8/x8 mode

### Software

- [Ubuntu Server](https://ubuntu.com/download/server) 25.10 or newer
- Server created with name `panther-minor`
- User `$USER` created during installation
- Server pre-installed with OpenSSH

## Setup

Generate a [Fine-grained token](https://github.com/settings/personal-access-tokens) with Read/Write access to
`panther-minor` repository.

Then, connect to the server via SSH, clone the repository using the PAT and run the setup script:

```bash
ssh <user>@<server-ip>
git clone https://github.com/rozsival/panther-minor.git
# Cloning into 'panther-minor'...
# Username for 'https://github.com': panther-minor
# Password for 'https://panther-minor@github.com': <PAT>
sudo bash panther-minor/setup.sh
```

> [!NOTE]
> You can discover the server IP after login on the host machine using `ip a` command.

The script will automatically configure:

- **Essential Packages** — `build-essential`, `jq`, `nvtop`, `llmfit`, etc. with auto updates
- **Docker** — installs Docker Engine and Docker Compose
- **Tailscale** — installs the Tailscale agent
- **SSH** — hardens `/etc/ssh/sshd_config` (port 2222, key-only auth, restricted users)
- **UFW** — sets up the firewall (ports 2222, 80, 443)
- **fail2ban** — installs and configures brute-force protection
- **AMD GPU & ROCm** — installs the latest kernel drivers and ROCm
- **Kernel Parameters** — configures GRUB with `amdgpu.mes=1 iommu=pt`
- **Git** — configures default name, email, and rebase pull strategy
- **Shell** — sets up a modern shell prompt for `$USER` user

> [!IMPORTANT]
> **Reboot is required** after the script completes to load the new kernel drivers and parameters.
> After reboot, SSH will be available on **port 2222** only.
> Reconnect with: `ssh -p 2222 <user>@<server-ip>`

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
