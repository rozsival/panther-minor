# 🛠️ Installation

> From bare metal to a running stack: hardware and BIOS requirements, a clean Ubuntu Server install, one
> `setup` command that prepares and hardens the host, then the tailnet the services are reached through.

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

### Software and accounts

- 🐧 [Ubuntu Server](https://ubuntu.com/download/server) **26.04 LTS or newer** (Linux kernel 7)
- A non-root user with `sudo` privileges, created during the OS install
- OpenSSH enabled during install (fetching allowed keys from GitHub is supported)
- A [Tailscale](https://tailscale.com/) tailnet you administer: the services are reached through a Tailscale node
  with a Tailscale-issued certificate, so no domain or certificate of your own is needed

> [!WARNING]
> **Install a major release cleanly rather than upgrading in place.** `do-release-upgrade` leaves the
> previous release's kernels installed and disables third-party repositories, so the out-of-tree
> `amdgpu` DKMS driver is rebuilt in a mixed state. Every build succeeds, the module loads, nothing
> fails — and inference throughput silently drops. Record a baseline with
> `./bin/panther-minor models llm bench <model>` before any OS, driver, ROCm or `llama.cpp` change so a regression
> is a diff rather than a hunch.

## 📦 Install

SSH into the server as the user who will operate the stack (not `root`) and run:

```bash
curl -fsSL https://github.com/rozsival/panther-minor/releases/latest/download/install.sh | bash
```

The installer downloads the latest release's runtime archive (`panther-minor.tar.gz`) into `~/panther-minor` — set
`PANTHER_MINOR_DIR` to install elsewhere (`curl … | PANTHER_MINOR_DIR=/srv/panther-minor bash`). It needs only `curl`
and `tar`, refuses a non-empty directory, and installs nothing else: host setup is the next step.

The archive holds only what the host runs: `bin/panther-minor`, `docker-compose.yml`, `.env.example`, the service
directories (`llama-cpp/`, `stable-diffusion-cpp/`, `monitoring/`, `proxy/nginx.conf`, `terminfo/`) and the model
catalogs. No `.git`, CLI sources, docs, tests or Node.js tooling: everything else runs in Docker. Its `.manifest`
lists the shipped files and `.release` the installed version, both read by [`update`](operations.md#-updating).

## 🚀 Run the setup

From the install directory:

```bash
cd ~/panther-minor
sudo ./bin/panther-minor setup
```

`setup` defaults to `setup all`, which prompts for the server name, allowed user, SSH port, timezone and LVM device
(each pre-filled from flags, `panther_*` environment variables or defaults), asks for confirmation, then runs every
step below in order.

> [!WARNING]
> **Reboot after setup** to load the new kernel driver and parameters. Afterwards SSH listens on **port 2222** with
> **key-based authentication only**: `ssh -p 2222 <user>@<server-ip>`.

### What `setup all` configures

| #   | Step        | What it does                                                                                                                                           |
| --- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | `init`      | Extends the LVM root volume (`/dev/ubuntu-vg/ubuntu-lv`) and sets the timezone (`Europe/Prague`)                                                       |
| 2   | `packages`  | `build-essential`, `jq`, `nvtop`, `htop` and more, plus unattended upgrades                                                                            |
| 3   | `brew`      | Homebrew, `llmfit` and Hugging Face CLI (`hf`) for the allowed user                                                                                    |
| 4   | `docker`    | Docker Engine + Compose; adds the allowed user to the `docker` group                                                                                   |
| 5   | `tailscale` | Tailscale agent for the host itself (SSH over the tailnet)                                                                                             |
| 6   | `ssh`       | Hardened `/etc/ssh/sshd_config`: port `2222`, key-only auth, `AllowUsers` restricted                                                                   |
| 7   | `ufw`       | Firewall rules: only SSH (`2222`) is open                                                                                                              |
| 8   | `fail2ban`  | Brute-force protection on the SSH port                                                                                                                 |
| 9   | `amdgpu`    | Latest AMD kernel driver (DKMS) and ROCm                                                                                                               |
| 10  | `grub`      | Kernel parameters `amdgpu.mes=1 amdgpu.runpm=0 iommu=pt pcie_aspm=off`                                                                                 |
| 11  | `shell`     | Starship prompt; Ghostty terminfo in `/etc/terminfo`; `panther-minor` on the allowed user's `PATH` with bash completion ([`install`](cli.md#-install)) |
| 12  | `env`       | Creates `.env` from `.env.example`, syncs `VIDEO_GID` / `RENDER_GID`, reminds you to set `TS_AUTHKEY`                                                  |

Steps that need follow-up register it, and the run ends with an **ACTIONS REQUIRED** list — typically: reboot,
open a second SSH session on the new port before closing the current one, authenticate Tailscale, and set
`TS_AUTHKEY`.

> [!TIP]
> Every step can be re-run on its own, e.g. `sudo ./bin/panther-minor setup ssh`. Flags per step are listed in the
> [CLI reference](cli.md#setup).

## 🔐 Connect the host to Tailscale

Optional for the services, which have their own tailnet node, but convenient for SSH. After the reboot, join the
server to your [tailnet](https://login.tailscale.com/admin/):

```bash
sudo tailscale up
```

Follow the printed link to authenticate, then reconnect through Tailscale: `ssh -p 2222 <user>@<server-name>`.

> [!IMPORTANT]
> Do not name the host or its node `panther-minor`: that name belongs to the services' sidecar, which would otherwise
> come up as `panther-minor-1`. See [Prepare the tailnet](#-prepare-the-tailnet) for renaming the host.

> [!TIP]
> [Disable key expiry](https://login.tailscale.com/admin/machines) for the server in Tailscale to avoid losing access.

## 🧭 Prepare the tailnet

The `ts-proxy` sidecar joins the tailnet as node `panther-minor` with the tag `tag:panther-minor`, terminates TLS with a
Tailscale certificate and forwards each service port to nginx — see [Networking & security](networking.md). It needs:

1. **MagicDNS and HTTPS Certificates** enabled in the [DNS settings](https://login.tailscale.com/admin/dns). The
   tailnet DNS name shown there is the `<tailnet>` in `https://panther-minor.<tailnet>.ts.net`.
2. **`tag:panther-minor` in `tagOwners`** of the [access controls](https://login.tailscale.com/admin/acls). If the
   policy no longer allows all traffic, also grant your devices the ports `8000`, `8001`, `8080`, `3000` and `9090`
   on `tag:panther-minor` — the snippet is in [Tailnet policy](networking.md#-tailnet-policy).
3. **An auth key** from [Settings → Keys](https://login.tailscale.com/admin/settings/keys): reusable, pre-approved,
   tagged `tag:panther-minor`. Put it in `.env`:

   ```bash
   TS_AUTHKEY=tskey-auth-…
   ```

   The sidecar uses it on its first login only; the node identity then lives in the `ts-proxy-state` volume, and as
   a tagged node it never expires.

4. **A host name other than `panther-minor`.** The host's own Tailscale node (if you add one, see
   [above](#-connect-the-host-to-tailscale)) takes the OS hostname. If the host is called `panther-minor`, the sidecar
   comes up as `panther-minor-1`, its certificate is issued for that name, and every
   `https://panther-minor.<tailnet>.ts.net` URL hits the host node, where nothing listens. Rename the host first:

   ```bash
   sudo hostnamectl set-hostname <name>
   sudo tailscale set --hostname=<name>   # if the host is on the tailnet
   ```

   Then update whatever reached the host by its old name (SSH config, bookmarks).

After the first `cluster start`, `panther-minor` appears in the
[machines list](https://login.tailscale.com/admin/machines) and the services answer on
`https://panther-minor.<tailnet>.ts.net:<port>`:

```bash
curl https://panther-minor.<tailnet>.ts.net:8000/v1/models
```

Upgrading an install from before the sidecar (own domain, `BIND_ADDR`)? Follow
[Migrating from the domain setup](networking.md#-migrating-from-the-domain-setup).

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

### `ts-proxy` logs a login URL instead of joining the tailnet. Why?

Its first login found no usable `TS_AUTHKEY`: the key is empty, expired, single-use and already spent, or not allowed
to apply `tag:panther-minor`. Create a new key as in [Prepare the tailnet](#-prepare-the-tailnet), put it in `.env`,
then `./bin/panther-minor cluster restart ts-proxy`.

### Can I change the defaults (user, SSH port, timezone, LVM device)?

Yes — through the interactive prompts, flags (`--allowed-user`, `--ssh-port`, `--timezone`, `--lvm-device`,
`--server-name`) or the matching `panther_*` environment variables. See [CLI reference](cli.md#setup).

### Do I need a domain or a TLS certificate?

No. The sidecar gets and renews a certificate for `panther-minor.<tailnet>.ts.net` itself; nginx serves plain HTTP
behind it.
