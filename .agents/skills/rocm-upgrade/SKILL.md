---
name: rocm-upgrade
description: >
  Upgrade ROCm, the amdgpu driver, the base OS, or the kernel across the whole Panther Minor stack.
  Use when the user says "upgrade ROCm", "bump the amdgpu driver", "new base image", "upgrade
  Ubuntu / the kernel in the stack", or "update the ROCm setup CLI".
---

You are upgrading the ROCm / amdgpu / base-OS / kernel version for Panther Minor. This is a
multi-file, easy-to-half-finish change — every occurrence below has to move together or the stack
ends up with a Docker image on one ROCm release and a host installer pinned to another.

**No assumptions are allowed.** File locations and version strings drift between releases; rediscover
them from the repo before editing rather than trusting any list below.

## 1. Discover the current versions

Do not trust a cached list of hits — run this yourself, right now, and enumerate every match:

```bash
grep -rn "rocm/dev-ubuntu-\|gfx1201\|GGML_HIP_RCCL\|amdgpu\.mes\|amdgpu\.runpm\|iommu=pt\|pcie_aspm" \
  --include=*.sh --include=Dockerfile --include=*.yml --include=*.md --include=*.example . \
  | grep -vE "node_modules|/\.git/"
grep -rn "amdgpu_release\|ubuntu_codename\|rocm_release\|rocm_distro\|amdrocm[0-9]" bin/src . \
  | grep -vE "node_modules|/\.git/"
grep -rniE "ubuntu [0-9]{2}\.04|rocm [0-9]+(\.[0-9]+)?|linux kernel [0-9]+" README.md AGENTS.md
```

As of the last verified pass, the version-carrying locations were:

| File                                | What it pins                                                                                                                               |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `bin/src/setup_amdgpu_command.sh`   | `amdgpu_release`, `ubuntu_codename`, `rocm_release`, `rocm_distro` locals; repo URLs; `amdrocm${rocm_release}-${rocm_arch}` package name   |
| `bin/src/setup_packages_command.sh` | `apt-get upgrade -y --with-new-pkgs` and the base package list (OS-version-sensitive names go here)                                        |
| `bin/src/setup_grub_command.sh`     | GRUB kernel params array (`amdgpu.mes=1 amdgpu.runpm=0 iommu=pt pcie_aspm=off`)                                                            |
| `bin/src/lib/setup.sh`              | Shared setup helpers invoked by the commands above — check for embedded version assumptions                                                |
| `llama-cpp/Dockerfile`              | `FROM rocm/dev-ubuntu-<ver>:<rocm-ver>-full`, `ARG ROCM_ARCH="gfx1201"`, `-DGGML_HIP_RCCL=ON`, `/etc/ld.so.conf.d/rocm.conf` registration  |
| `stable-diffusion-cpp/Dockerfile`   | Same base image, `ROCM_ARCH`, dynamic-loader registration as `llama-cpp/Dockerfile`                                                        |
| `docker-compose.yml`                | Descriptive comments ("ROCm 10 support") near the `llama-cpp` and `stable-diffusion-cpp` service blocks; `ROCM_ARCH` build arg passthrough |
| `.env.example`                      | `ROCM_ARCH=gfx1201` (only changes if the target GPU's ISA changes, not on every ROCm bump)                                                 |
| `README.md`                         | Platform badge, "Ubuntu Server **26.04 LTS or newer** (Linux kernel 7)" prerequisite, ROCm 10 mentions in the services table               |
| `AGENTS.md`                         | "Host: Ubuntu 26.04 LTS+ (Linux kernel 7), ROCm 10, kernel params ..." stack summary line, "ROCm v10 with gfx1201" rule                    |
| `models/README.md`                  | Incidental hardware-context prose (e.g. base image name in a footnote) — check, don't assume it needs a change                             |

`bin/cli` is a ~7,700-line generated bashly artifact assembled from `bin/src/*` by
`pnpm run build:cli` (see `package.json`). **Never hand-edit `bin/cli` directly** — edit the source
command file under `bin/src/`, then regenerate.

## 2. Check upstream AMD instructions first

Before changing a single line, read AMD's current install instructions for the **target** Ubuntu
release at https://rocm.docs.amd.com/en/latest/install/rocm.html. Confirm:

- the APT repo URL layout for driver (`repo.radeon.com/amdgpu/<release>/ubuntu`) and ROCm
  (`stable.repo.amd.com/rocm/core/packages/<distro>/`) — copy them **verbatim**, do not guess at a
  pattern from the old version;
- the signing key URLs and whether AMD still uses two separate keys (driver key vs. ROCm key) or has
  consolidated them;
- the ROCm-arch metapackage name pattern (has changed across releases: `rocm`/`rocm-core` →
  `amdrocm7.14-gfx1201` → `amdrocm10.0-gfx1201`) — get the new pattern exactly, it feeds
  `"amdrocm${rocm_release}-${rocm_arch}"` in `setup_amdgpu_command.sh`;
- whether `amdgpu-install` is still the recommended path or whether AMD still documents the direct
  package-manager path this repo uses instead (see the comment above `panther_setup_amdgpu` explaining
  why `amdgpu-install` was dropped — re-verify that reasoning still holds for the new release before
  reintroducing it).

## 3. Apply the version bump

1. **`bin/src/setup_amdgpu_command.sh`** — update `amdgpu_release`, `ubuntu_codename`, `rocm_release`,
   `rocm_distro` to match what AMD documents. Update the `.sources` file bodies (`Suites:`, `URIs:`)
   and the purge/reinstall comments referencing old metapackage name patterns if they've changed
   again. Read the whole function before editing — several comments encode hard-won behavior (why
   `amdgpu-install` is skipped, why packages are purged wholesale, why the driver-version compare uses
   a prefix match) that must stay accurate after the edit, not just the version literals.
2. **`bin/src/setup_grub_command.sh`** — GRUB params are a Linux-kernel/GPU-generation concern, not a
   ROCm-release one. Only touch `amdgpu.mes=1 amdgpu.runpm=0 iommu=pt pcie_aspm=off` if the new kernel
   or driver release changes what's required — check AMD's release notes for the target ROCm version
   for new/removed recommended kernel params before editing this file at all.
3. **`bin/src/setup_packages_command.sh`** — if the OS codename changed, verify every package name in
   the install list still exists under the new release's APT repos; some Ubuntu package names get
   renamed across LTS releases.
4. **`llama-cpp/Dockerfile`** and **`stable-diffusion-cpp/Dockerfile`** — bump
   `FROM rocm/dev-ubuntu-<ver>:<rocm-ver>-full` in both files to the same new tag. Keep
   `ARG ROCM_ARCH="gfx1201"` and `-DGGML_HIP_RCCL=ON` unless the target GPU generation changed (that's
   a separate decision from a ROCm/OS bump). Re-check the `/etc/ld.so.conf.d/rocm.conf` +
   `ldconfig` block: it exists because AMD's TheRock-built base image ships no dynamic-loader entry
   for `/opt/rocm/lib`; confirm the new base image still lacks one (if AMD started shipping the entry,
   the workaround becomes dead weight and should be dropped, with the explanatory comment removed
   too).
5. **`README.md`** — update the platform badge, the "Ubuntu Server **X.Y LTS or newer** (Linux kernel
   N)" prerequisite line, and the "ROCm N support" mentions in the services table.
6. **`AGENTS.md`** — update the "Host: Ubuntu X.Y LTS+ (Linux kernel N), ROCm N, kernel params ..."
   line and the "ROCm vN with gfx1201" rule under Critical Rules.
7. **`docker-compose.yml`** — update the descriptive "ROCm N support" comments near the two build
   blocks; these are documentation only; no functional change expected.

Do **not** touch `.env.example`'s `ROCM_ARCH` unless the target GPU's ISA is actually changing — that
value is independent of the ROCm/OS version.

## 4. `apt-get`, never bare `apt`

Every script and Dockerfile in this repo uses `apt-get`, never `apt`: `apt` has no stable CLI
interface and prints a warning on every scripted invocation.

- `apt upgrade` is not `apt-get upgrade` — it maps to `apt-get upgrade -y --with-new-pkgs`. Plain
  `apt-get upgrade` holds back any upgrade that needs a new package, which is exactly what a kernel
  ABI bump is (a new `linux-image` pulled in by `linux-generic`). `setup_packages_command.sh` already
  gets this right — preserve it if you touch that file.
- Use `apt-cache` / `apt-mark` for read-only queries (available versions, held packages), never
  `apt`.

## 5. Verify

1. **Syntax-check every changed shell script**:
   ```bash
   bash -n bin/src/setup_amdgpu_command.sh
   bash -n bin/src/setup_packages_command.sh
   bash -n bin/src/setup_grub_command.sh
   bash -n bin/src/lib/setup.sh
   ```
2. **Regenerate the CLI artifact** from the edited source (never hand-edit `bin/cli`):
   ```bash
   pnpm run build:cli
   ```
3. **Rebuild the images** with the new base image / ROCm packages:
   ```bash
   ./bin/cli cluster build --no-cache
   ```
4. **Start the stack** and confirm the GPU is visible with the right ISA:
   ```bash
   ./bin/cli cluster start
   ```
   Then check the container logs (`./bin/cli logs llama-cpp --tail 200`, same for
   `stable-diffusion-cpp`) for successful ROCm/HIP init (no `librccl.so.1` or `libamdhip64`/`libhipblas` "cannot open
   shared object file" errors — those specifically mean the `/etc/ld.so.conf.d/rocm.conf` step broke
   or the base image changed layout) and confirm the reported GPU/gfx target matches `gfx1201`.
5. **Prove nothing stale remains** — grep the repo for the **old** version strings (base image tag,
   `amdgpu_release`, `rocm_release`, `rocm_distro`, Ubuntu codename/version, kernel version) across the
   same file types as step 1. It must return nothing except intentional history (e.g. old comments
   explaining _why_ a prior release did something differently, or `CHANGELOG`-style content):
   ```bash
   grep -rn "<OLD_ROCM_RELEASE>\|<OLD_UBUNTU_VERSION>\|<OLD_AMDGPU_RELEASE>\|<OLD_BASE_IMAGE_TAG>" \
     --include=*.sh --include=Dockerfile --include=*.yml --include=*.md --include=cli . \
     | grep -vE "node_modules|/\.git/|CHANGELOG"
   ```
   If anything unexpected prints, update it before continuing.
6. On real hardware, confirm the host side: `modinfo amdgpu | head -3` reports the new driver version
   after reboot, and `rocminfo` / `rocm-smi` (if available) reports `gfx1201` under the new ROCm
   release.

## 6. Commit guidance

Conventional Commits v1.0.0, lowercase, no final punctuation, ≤100 chars.

- If the bump changes a **host requirement** the user must act on before the stack works again (new
  Ubuntu release the host must be reinstalled/upgraded to, a required reboot, a dropped/renamed kernel
  param) — this is breaking: use `feat!:` with a commit body explaining the exact host action
  required, e.g.:
  ```
  feat!: upgrade stack to rocm 10.0 and amdgpu 31.50

  Host must be running Ubuntu 26.04 LTS (resolute) before re-running `./bin/cli setup`. Reboot
  after setup to load the new amdgpu kernel module.
  ```
- Otherwise, scope by what actually changed:
  - `feat(rocm): upgrade stack to rocm <ver> and amdgpu <release>` for the version-bump commit itself.
  - `fix(setup): <describe>` for CLI-side correctness fixes uncovered along the way (e.g. a version
    comparison that broke because the new driver changed its version string format — this repo has
    hit this before with "compare amdgpu driver versions by upstream prefix", where `dkms` and
    `modinfo` spell the same driver version differently and an equality check false-positived on
    every run).
  - `feat: register ROCm with dynamic loader in Dockerfile` (or similar, scoped `docker`/`llama-cpp`)
    if the base image swap requires adding/removing the `/etc/ld.so.conf.d/rocm.conf` workaround.

Split unrelated fixes discovered mid-upgrade into their own commits rather than folding everything
into one oversized `feat(rocm)` commit.
