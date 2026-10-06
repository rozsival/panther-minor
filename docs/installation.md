# 🛠️ Installation

> From bare metal to a running stack: hardware and BIOS requirements, a clean Ubuntu Server install, one
> `setup` command that prepares and hardens the host, then Tailscale and TLS certificates.

**Related:** [Networking & security](networking.md) · [Operations](operations.md) · [CLI reference](cli.md) ·
[Architecture](architecture.md)

---

## 🧰 Prerequisites

### Hardware

| Component   | Recommendation                                        |
| ----------- | ----------------------------------------------------- |
| Motherboard | X870E with 2x PCIe Gen5 x16 slots                     |
| CPU         | AMD Ryzen 9 or newer, **12 cores recommended**        |
| Memory      | **96 GB DDR5 or more**, in **two DIMMs**              |
| GPUs        | **2x AMD Radeon Pro RDNA 4** with **32 GB VRAM each** |
| Storage     | NVMe SSD, **1 TB or more**, Gen4 or newer             |
| PSU         | **1300W or more** with 2x 12VHPWR connectors          |

> [!NOTE]
> Use **two DIMMs, one per channel**. Filling all four slots forces AM5 down to the JEDEC 3600 MT/s fallback
> regardless of EXPO, and adding modules later downclocks the pair already installed. DRAM speed measured no
> effect on MoE inference here, so size for **capacity**: spare RAM becomes page cache for the GGUF corpus
> and shortens cold model loads.

### BIOS

| Setting           | Value                                                                        |
| ----------------- | ---------------------------------------------------------------------------- |
| Above 4G decoding | Enabled                                                                      |
| Resize BAR        | Enabled                                                                      |
| IOMMU             | Enabled                                                                      |
| iGPU              | Disabled                                                                     |
| PCIe GPU slots    | Gen5 (the CPU bifurcates its x16 into x8/x8, so each card trains at Gen5 x8) |
| `M2_1` slot       | Gen4 for the NVMe SSD                                                        |

> [!NOTE]
> Gen5 GPU + Gen4 SSD is the sweet spot for maximizing GPU performance while maintaining system stability.

### Software and accounts

- 🐧 [Ubuntu Server](https://ubuntu.com/download/server) **26.04 LTS or newer** (Linux kernel 7)
- A non-root user with `sudo` privileges, created during the OS install
- OpenSSH enabled during install (fetching allowed keys from GitHub is supported)
- A [Tailscale](https://tailscale.com/) account for secure remote access
- A domain you control, required for TLS certificate issuance and secure service access

> [!WARNING]
> **Install a major release cleanly rather than upgrading in place.** `do-release-upgrade` leaves the
> previous release's kernels installed and disables third-party repositories, so the out-of-tree
> `amdgpu` DKMS driver is rebuilt in a mixed state. Every build succeeds, the module loads, nothing
> fails — and inference throughput silently drops. Record a baseline with
> `./bin/panther-minor models llm bench <model>` before any OS, driver, ROCm or `llama.cpp` change so a regression
> is a diff rather than a hunch.

## 🚀 Run the setup

SSH into the server, clone the repository at a release tag (see the [root README](../README.md#-quick-start) for
the current one) and run:

```bash
sudo ./bin/panther-minor setup
```

`setup` defaults to `setup all`, which prompts for the server name, allowed user, SSH port, timezone and LVM device
(each pre-filled from flags, `panther_*` environment variables or defaults), asks for confirmation, then runs every
step below in order.

> [!WARNING]
> **Reboot after setup** to load the new kernel driver and parameters. Afterwards SSH listens on **port 2222** with
> **key-based authentication only**: `ssh -p 2222 <user>@<server-ip>`.

### What `setup all` configures

| #   | Step        | What it does                                                                                                      |
| --- | ----------- | ----------------------------------------------------------------------------------------------------------------- |
| 1   | `init`      | Extends the LVM root volume (`/dev/ubuntu-vg/ubuntu-lv`) and sets the timezone (`Europe/Prague`)                  |
| 2   | `packages`  | `build-essential`, `jq`, `nvtop`, `htop` and more, plus unattended upgrades                                       |
| 3   | `brew`      | Homebrew, `llmfit`, Hugging Face CLI (`hf`) and `yq` for the allowed user                                         |
| 4   | `docker`    | Docker Engine + Compose; adds the allowed user to the `docker` group                                              |
| 5   | `tailscale` | Tailscale agent                                                                                                   |
| 6   | `ssh`       | Hardened `/etc/ssh/sshd_config`: port `2222`, key-only auth, `AllowUsers` restricted                              |
| 7   | `ufw`       | Firewall rules for ports `2222`, `80` and `443`                                                                   |
| 8   | `fail2ban`  | Brute-force protection on the SSH port                                                                            |
| 9   | `amdgpu`    | Latest AMD kernel driver (DKMS) and ROCm                                                                          |
| 10  | `grub`      | Kernel parameters `amdgpu.mes=1 amdgpu.runpm=0 iommu=pt pcie_aspm=off`                                            |
| 11  | `git`       | Default name, email and rebase pull strategy                                                                      |
| 12  | `shell`     | Starship prompt; `panther-minor` on the allowed user's `PATH` with bash completion ([`install`](cli.md#-install)) |
| 13  | `env`       | Creates `.env` from `.env.example`, syncs `VIDEO_GID` / `RENDER_GID`, fills `BIND_ADDR`                           |

Steps that need follow-up register it, and the run ends with an **ACTIONS REQUIRED** list — typically: reboot,
open a second SSH session on the new port before closing the current one, authenticate Tailscale, and set
`BIND_ADDR`.

> [!TIP]
> Every step can be re-run on its own, e.g. `sudo ./bin/panther-minor setup ssh`. Flags per step are listed in the
> [CLI reference](cli.md#setup).

## 🔐 Connect Tailscale

After the reboot, join the server to your [Tailscale network](https://login.tailscale.com/admin/):

```bash
sudo tailscale up
```

Follow the printed link to authenticate, then reconnect through Tailscale and record the node's address in `.env` —
this is what scopes every published port away from the public internet:

```bash
ssh -p 2222 <user>@<server-name>
sudo ./bin/panther-minor setup env
```

> [!IMPORTANT]
> `setup all` runs before Tailscale is authenticated, so `BIND_ADDR` is empty until this step. The cluster refuses to
> start with an empty `BIND_ADDR` rather than publishing its ports on `0.0.0.0` — see
> [Networking & security](networking.md).

> [!TIP]
> [Disable key expiry](https://login.tailscale.com/admin/machines) for the server in Tailscale to avoid losing access.

## 🔒 Issue TLS certificates

Every service is served over HTTPS by the `proxy`, which loads `proxy/ssl/fullchain.pem` and `proxy/ssl/privkey.pem`.

1. Enable HTTPS in the Tailscale [DNS settings](https://login.tailscale.com/admin/dns).
2. At your DNS provider, add an `A` record pointing your (sub)domain to the server's
   [Tailscale IP address](https://login.tailscale.com/admin/machines).
3. Issue the certificate:

   ```bash
   ./bin/panther-minor proxy certbot --domain [<subdomain>.]<domain> --challenge-record _acme-challenge[.<subdomain>]
   ```

   > [!IMPORTANT]
   > The command prints the ACME DNS `CNAME` record value. Add that record at your DNS provider before continuing,
   > otherwise issuance fails.

4. Enable automatic daily renewal (default schedule `0 2 * * *`, log `proxy/renew-ssl.log`):

   ```bash
   ./bin/panther-minor proxy setup-cron
   ```

## ✅ Next steps

1. Download models — [Models](models.md#-managing-weights)
2. Start the cluster — [Operations](operations.md#-cluster-lifecycle)
3. Optionally add a Hugging Face token to `.env` — [Operations](operations.md#-configuration)

---

## ❓ FAQ

### Can I upgrade Ubuntu in place with `do-release-upgrade`?

Don't. Leftover kernels and disabled third-party repos leave the `amdgpu` DKMS driver in a mixed state that loses
throughput silently. `setup amdgpu` warns when it finds modules built for other kernels. Reinstall cleanly and
compare against a `models llm bench` baseline.

### I lost SSH access after `setup ssh`. What happened?

SSH moved to port `2222` with key-only auth and an `AllowUsers` list. Always open a second session on the new port
before closing the current one, and connect with `ssh -p 2222 <user>@<host>`.

### `cluster start` fails mentioning `BIND_ADDR`. Why?

`BIND_ADDR` is empty because Tailscale was not up when `setup env` ran. Run `sudo tailscale up`, then
`sudo ./bin/panther-minor setup env`.

### Can I change the defaults (user, SSH port, timezone, LVM device)?

Yes — through the interactive prompts, flags (`--allowed-user`, `--ssh-port`, `--timezone`, `--lvm-device`,
`--server-name`) or the matching `panther_*` environment variables. See [CLI reference](cli.md#setup).

### Do I really need a domain?

Yes. The proxy serves every port over TLS and needs a certificate issued through ACME DNS for a domain you control.
