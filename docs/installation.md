# 🛠️ Installation

> From bare metal to a running stack: hardware and BIOS requirements, a clean Ubuntu Server install with Docker
> (recommended: [Pantheon](https://github.com/rozsival/pantheon)), one `setup` command that prepares the host for the
> GPU stack, then the tailnet the services are reached through.

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

- 🐧 [Ubuntu Server](https://ubuntu.com/download/server) **26.04 LTS** (Linux kernel 7)
- A non-root user with `sudo` privileges, created during the OS install
- OpenSSH enabled during install (fetching allowed keys from GitHub is supported)
- **Docker Engine + Compose**, with that user in the `docker` group. Recommended:
  [Pantheon](https://github.com/rozsival/pantheon), the baseline this stack runs on, which also hardens SSH and sets up
  a firewall, fail2ban and unattended upgrades. Any host with Docker from
  [Docker's repository](https://docs.docker.com/engine/install/ubuntu/) works too.
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
directories (`llama-cpp/`, `stable-diffusion-cpp/`, `monitoring/`, `proxy/nginx.conf`) and the model
catalogs. No `.git`, CLI sources, docs, tests or Node.js tooling: everything else runs in Docker. Its `.manifest`
lists the shipped files and `.release` the installed version, both read by [`update`](operations.md#-updating).

## 🚀 Run the setup

From the install directory:

```bash
cd ~/panther-minor
sudo ./bin/panther-minor setup
```

`setup` defaults to `setup all`, which prompts for the allowed user (pre-filled from `--allowed-user`, the
`PANTHER_ALLOWED_USER` environment variable or the `sudo` caller), asks for confirmation, then runs every step below in
order. It changes nothing on a host that fails `check`.

> [!WARNING]
> **Reboot after setup** to load the new kernel driver and parameters.

### What `setup all` configures

| #   | Step      | What it does                                                                                                      |
| --- | --------- | ----------------------------------------------------------------------------------------------------------------- |
| 1   | `check`   | Stops unless Ubuntu 26.04 and a running Docker Engine + Compose are there; warns if the user is not in `docker`   |
| 2   | `deps`    | `jq`, `augeas-tools`, `nvtop`, `python3-venv`; the Hugging Face CLI (`hf`) for the allowed user in `~/.local/bin` |
| 3   | `amdgpu`  | Latest AMD kernel driver (DKMS) and ROCm                                                                          |
| 4   | `grub`    | Kernel parameters `amdgpu.mes=1 amdgpu.runpm=0 iommu=pt pcie_aspm=off`                                            |
| 5   | `memory`  | The `llm.slice` systemd unit that keeps llama.cpp's weights in memory ([details](llm.md#host-memory-protection))  |
| 6   | `env`     | Creates `.env` from `.env.example`, syncs `VIDEO_GID` / `RENDER_GID`, reminds you to set `TS_AUTHKEY`             |
| 7   | `install` | `panther-minor` on the allowed user's `PATH` with bash completion ([`install`](cli.md#-install))                  |

Steps that need follow-up register it, and the run ends with an **ACTIONS REQUIRED** list — typically: reboot, set
`TS_AUTHKEY`, and log in again if the user was just added to the `docker` group. A step run on its own ends with its
own list.

`setup` does not touch SSH, the firewall, the timezone or anything else outside the GPU stack: that is the host
baseline's job. `./bin/panther-minor setup check` changes nothing and needs no `sudo`, so it is a quick way to see
whether a host is ready.

> [!TIP]
> Every step can be re-run on its own, e.g. `sudo ./bin/panther-minor setup grub`. Flags per step are listed in the
> [CLI reference](cli.md#setup).

> [!NOTE]
> SSH over the tailnet needs the host itself on Tailscale, separately from the services' sidecar:
> [Pantheon](https://github.com/rozsival/pantheon/blob/main/docs/installation.md) installs the agent, then
> `sudo tailscale up`. Do not name that node `panther-minor` (see [Prepare the tailnet](#-prepare-the-tailnet)).

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
   a tagged node it never expires. Clear `TS_AUTHKEY` and revoke the key once `ts-proxy` is healthy.

   With [Tailnet Lock](networking.md#tailnet-lock-highly-recommended) — highly recommended — sign the key on one of
   your signing nodes first and put the signed key it prints in `.env` instead, or the sidecar joins locked out. A
   signed key gets past the lock for whoever holds it, so make it single-use rather than reusable, and do the clearing
   and revoking above without fail:

   ```bash
   tailscale lock sign tskey-auth-…
   ```

4. **A host name other than `panther-minor`.** The host's own Tailscale node (if you add one, see
   [above](#what-setup-all-configures)) takes the OS hostname. If the host is called `panther-minor`, the sidecar
   comes up as `panther-minor-1`, its certificate is issued for that name, and every
   `https://panther-minor.<tailnet>.ts.net` URL hits the host node, where nothing listens. Rename the host first:

   ```bash
   sudo hostnamectl set-hostname <name>
   sudo sed -i 's/\bpanther-minor\b/<name>/g' /etc/hosts   # the 127.0.1.1 line, or sudo cannot resolve the host
   sudo tailscale set --hostname=<name>                     # if the host is on the tailnet
   ```

   Then update whatever reached the host by its old name (SSH config, bookmarks, Funnel URLs served by the host
   node).

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

### I already ran the old `setup all`. Do I need Pantheon?

No. Up to version 15, `setup all` also installed the host baseline (packages, Docker, Tailscale, SSH hardening, UFW,
fail2ban, Homebrew, Starship): all of that stays on the host as it is, and nothing needs to be re-run. Pantheon now
owns those steps (`./bin/pantheon setup <step>`) if you want to re-apply one later. Homebrew's `hf` keeps working; a
fresh `setup deps` installs `hf` only where none is found. `llmfit` is no longer installed by `setup`: see
[Models](models.md).

### `ts-proxy` logs a login URL instead of joining the tailnet. Why?

Its first login found no usable `TS_AUTHKEY`: the key is empty, expired, single-use and already spent, or not allowed
to apply `tag:panther-minor`. Create a new key as in [Prepare the tailnet](#-prepare-the-tailnet), put it in `.env`,
then `./bin/panther-minor cluster restart ts-proxy`.

### Which settings does `setup` take?

Only the allowed user: the prompt, `--allowed-user` or `PANTHER_ALLOWED_USER`. The SSH port, timezone, storage and
server name moved to [Pantheon](https://github.com/rozsival/pantheon) together with the steps that used them. See
[CLI reference](cli.md#setup).

### Do I need a domain or a TLS certificate?

No. The sidecar gets and renews a certificate for `panther-minor.<tailnet>.ts.net` itself; nginx serves plain HTTP
behind it.
