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

## ADM GPU Kernel with ROCm

> [!WARNING]
> You should disable the iGPU in the BIOS for ROCm to work properly. Ensure you have a DisplayPort connected to the dedicated GPU.

Follow the instructions at [AMD Docs](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/install-methods/package-manager/package-manager-ubuntu.html) to install ROCm.
