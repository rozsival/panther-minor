# 🐆 Panther Minor

The AI Workstation setup.

## Pre-requisites

- Ubuntu Server 25.10 or newer
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

- **SSH** — hardens `/etc/ssh/sshd_config` (port 2222, key-only auth, restricted users)
- **UFW** — sets up the firewall (ports 2222, 80, 443)
- **fail2ban** — installs and configures brute-force protection

> [!WARNING]
> After the script completes, SSH will be available on **port 2222** only.
> Reconnect with: `ssh -p 2222 <user>@<server-ip>`

## Tailscale

Follow the instructions at [Tailscale Docs](https://tailscale.com/docs/install/ubuntu/ubuntu-2510) to add the server to Tailscale.

Connect to the server via Tailscale:

```bash
ssh -p 2222 <user>@panther-minor
```

> [!WARNING]
> You need to be connected to Tailscale to access the server every time.
