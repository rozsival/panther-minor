# 🐆 Panther Minor

The AI Workstation Setup – light-weight, secure, and optimized LLaMA.cpp cluster on AMD Ryzen with RDNA 4 GPUs.

## Pre-requisites

### Hardware

- x870e motherboard with 2x PCIe Gen5 x16 slots
- AMD Ryzen 9 or newer (16+ cores recommended)
- 96 GB RAM DDR5 or more
- 2x AMD Radeon Pro with RDNA 4 (32 GB VRAM each)
- NVMe SSD (1 TB or more, Gen4 or newer)
- 1300W PSU or higher (depending on GPU TDP)

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
- Server installed with name and non-root user (with sudo privileges)
- Server installed with OpenSSH (fetch allowed keys from GitHub)
- [Tailscale](https://tailscale.com/) account for secure remote access

## Setup

Clone the repository and run the setup CLI on the server:

> [!WARNING]
> **Reboot is required** after the script completes to load new kernel drivers and parameters.
> After reboot, SSH will be available on **port 2222** and with **key-based authentication only**.
>
> Reconnect with: `ssh -p 2222 <user>@<server-ip>`

```bash
ssh <user>@<server-ip>
git clone https://github.com/rozsival/panther-minor.git
cd panther-minor
sudo ./bin/cli setup
```

> [!TIP]
> You can discover the server IP after login on the host machine using `ip a` command.

The command will automatically configure:

- **Init** — sets up server workspace with full disk capacity and timezone to `Europe/Prague`
- **Essential Packages** — `build-essential`, `jq`, `nvtop`, `htop`, etc. with auto updates
- **Homebrew** — installs Homebrew,`llmfit` and `huggingface-cli` for current user
- **Docker** — installs Docker Engine and Docker Compose
- **Tailscale** — installs the Tailscale agent
- **SSH** — hardens `/etc/ssh/sshd_config` (port 2222, key-only auth, restricted users)
- **UFW** — sets up the firewall (ports 2222, 80, 443)
- **fail2ban** — installs and configures brute-force protection
- **AMD GPU & ROCm** — installs the latest kernel drivers and ROCm
- **Kernel Parameters** — configures GRUB with `amdgpu.mes=1 iommu=pt`
- **Git** — configures default name, email, and rebase pull strategy
- **Shell** — sets up a modern shell prompt for current user
- **Environment** — creates `.env` from `.env.example` and syncs `VIDEO_GID` / `RENDER_GID`

> [!TIP]
> You can also run individual setup subcommands, e.g. to re-run SSH hardening:
>
> ```bash
> sudo ./bin/cli setup ssh
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
ssh -p 2222 <user>@<server-name>
```

> [!TIP]
> Most likely, you want to [Disable key expiry](https://login.tailscale.com/admin/machines) for the server
> in Tailscale to avoid losing access.

### SSL

All services in the cluster are configured to use self-signed SSL certificates for secure local access. Enabling SSL
requires manual steps:

1. Enable HTTPS in Tailscale [DNS settings](https://login.tailscale.com/admin/dns).

2. Add DNS type A record pointing to the
	 server's [Tailscale IP address](https://login.tailscale.com/admin/machines) in
	 your DNS provider to access the services via `<domain>`.

3. Generate Certbot certificate on the server:

> [!IMPORTANT]
> The script will output required ACME DNS CNAME record value. You MUST add this CNAME record to your DNS provider to
> complete the certificate issuance. The script will wait for you to confirm you completed this step. Do NOT continue
> until you have added the CNAME record, otherwise the certificate generation will fail.

```bash
./bin/cli proxy certbot --domain <domain> --challenge-record _acme-challenge.panther
```

4. Setup certificates auto renewal:

```bash
./bin/cli proxy setup-cron
```

## LLaMA.cpp Cluster

Runs a local LLM across both GPUs with an OpenAI-compatible API, plus a monitoring stack.

### Configuration

See `.env` for configurable parameters. Defaults are provided for all non-sensitive values.

> [!NOTE]
> It is highly recommended to set `HF_TOKEN` in `.env` with a [valid token](https://huggingface.co/settings/tokens) to
> avoid rate limits when downloading models from Hugging Face.

### Model Management

See [Models](./models/README.md) for available LLMs and their usage.

### Run the Cluster

To build and start the cluster, run:

```bash
./bin/cli cluster start
```

To only rebuild the cluster without starting:

```bash
./bin/cli cluster build
# or without cache (e.g. after config changes):
./bin/cli cluster build --no-cache
```

### Services

| Service               | Credentials       |
|-----------------------|-------------------|
| OpenAI-compatible API | —                 |
| Open WebUI (chat)     | —                 |
| Grafana (monitoring)  | `admin` / `admin` |
| Prometheus            | —                 |

> [!IMPORTANT]
> Services are NOT accessible from the public internet. See [PORTS.md](PORTS.md) for details.

### Stop

```bash
./bin/cli cluster stop
```

### CLI

See [Panther Minor CLI](./bin/README.md) for all available commands to manage the cluster.
