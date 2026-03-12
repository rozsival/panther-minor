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
- M2_1 slot set to Gen4 for NVMe SSD

> [!NOTE]
> Gen5 GPU vs Gen4 SSD is the sweet spot for maximizing GPU performance while maintaining system stability.

### Software

- [Ubuntu Server](https://ubuntu.com/download/server) 25.10 or newer
- Server installed with name `panther-minor`
- User `vit` created during installation
- Server installed with OpenSSH (fetch allowed keys from GitHub)

## Setup

Generate a [Fine-grained token](https://github.com/settings/personal-access-tokens) with Read access to
`panther-minor` repository.

Then, connect to the server via SSH, clone the repository using the PAT and run the setup script:

> [!WARNING]
> **Reboot is required** after the script completes to load new kernel drivers and parameters.
> After reboot, SSH will be available on **port 2222** and with **key-based authentication only**.
>
> Reconnect with: `ssh -p 2222 vit@<server-ip>`

```bash
ssh vit@<server-ip>
git clone https://x-access-token:<PAT>@github.com/rozsival/panther-minor.git
sudo bash panther-minor/setup.sh
```

> [!TIP]
> You can discover the server IP after login on the host machine using `ip a` command.

The script will automatically configure:

- **Disk** — extends LVM logical volume to full disk capacity (`ubuntu-vg/ubuntu-lv`)
- **Essential Packages** — `build-essential`, `jq`, `nvtop`, `htop`, etc. with auto updates
- **Homebrew** — installs Homebrew,`llmfit` and `huggingface-cli` for `vit` user
- **Docker** — installs Docker Engine and Docker Compose
- **Tailscale** — installs the Tailscale agent
- **SSH** — hardens `/etc/ssh/sshd_config` (port 2222, key-only auth, restricted users)
- **UFW** — sets up the firewall (ports 2222, 80, 443)
- **fail2ban** — installs and configures brute-force protection
- **AMD GPU & ROCm** — installs the latest kernel drivers and ROCm
- **Kernel Parameters** — configures GRUB with `amdgpu.mes=1 iommu=pt`
- **Git** — configures default name, email, and rebase pull strategy
- **Shell** — sets up a modern shell prompt for `vit` user
- **Environment** — creates `.env` from `.env.example` and syncs `VIDEO_GID` / `RENDER_GID`

> [!TIP]
> You can also run individual scripts from `scripts/` for specific configurations, e.g. to re-run SSH hardening:
> ```bash
> sudo bash panther-minor/scripts/05-ssh.sh
> ```

### Tailscale

After the system setup and reboot, authenticate the server to
your [Tailscale network](https://login.tailscale.com/admin/):

```bash
sudo tailscale up
```

Follow the link in your browser to complete the authentication. Once connected, you can access the server via its
Tailscale IP or hostname:

```bash
ssh -p 2222 vit@panther-minor
```

> [!TIP]
> Most likely, you want to [Disable key expiry](https://login.tailscale.com/admin/machines) for `panther-minor` machine
> in Tailscale to avoid losing access.

## LLaMA.cpp Cluster

Runs a local LLM across both GPUs with an OpenAI-compatible API, plus a monitoring stack.

### Configuration

See `.env` for configurable parameters. Defaults are provided for all variables.

> [!NOTE]
> It is highly recommended to set `HF_TOKEN` in `.env` with a [valid token](https://huggingface.co/settings/tokens) to
> avoid rate limits when downloading models from Hugging Face.

### Model Management

See [Models](./models/README.md) for supported models and their usage.

### Run the Cluster

To build and start the cluster, run:

```bash
make start
```

To only rebuild the cluster without starting:

```bash
make build
# or without cache (e.g. after config changes):
make build-no-cache
```

### Services

| Service               | URL                            | Credentials       |
|-----------------------|--------------------------------|-------------------|
| OpenAI-compatible API | `http://panther-minor:8000/v1` | —                 |
| Open WebUI (chat)     | `http://panther-minor:8080`    | —                 |
| Grafana (monitoring)  | `http://panther-minor:3000`    | `admin` / `admin` |
| Prometheus            | `http://panther-minor:9090`    | —                 |

> [!IMPORTANT]
> Services are NOT accessible from the public internet. See [PORTS.md](PORTS.md) for details.

### Stop

```bash
make stop
```
