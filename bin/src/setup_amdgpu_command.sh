panther_setup_amdgpu() {
  panther_prepare_setup_step 'Install AMD GPU kernel drivers and ROCm.'

  # The two halves of the stack come from two repositories on separate release
  # trains: the amdgpu kernel driver from repo.radeon.com/amdgpu, and ROCm from
  # stable.repo.amd.com. Both are published per distro release, so the driver
  # train, the Ubuntu codename and the ROCm repository's distro directory are
  # pinned here and have to be reviewed as a set whenever the host's release
  # changes.
  local amdgpu_release='31.50'
  local ubuntu_codename='resolute'
  local rocm_release='10.0'
  local rocm_distro='ubuntu2604'

  # Selects the arch-specific ROCm metapackage. Pinned instead of installing the
  # target-agnostic 'amdrocm10.0', which depends on the metapackage of every gfx
  # target AMD builds and would pull ~25 runtimes this host has no GPU for.
  local rocm_arch="${ROCM_ARCH:-gfx1201}"

  # amdgpu-install is deliberately not used any more. Its 31.50 bundle registers
  # repo.radeon.com/rocmradeon/apt/26.14, which carries a 10.0.0~pre build of
  # ROCm, while the package-manager path AMD documents for gfx1201 installs the
  # released 10.0.0 from stable.repo.amd.com. Losing it also loses the
  # '--usecase=rocm,graphics' selection, which on this headless host only ever
  # pulled the empty amdgpu-core/amdgpu-lib/amdgpu-multimedia metapackages.
  panther_log_info 'Removing any previous AMD GPU & ROCm installation...'

  # Purged wholesale rather than by name: the metapackage names carry the ROCm
  # release ('rocm' and 'rocm-core' up to 7.2, 'amdrocm7.14-gfx1201' after that,
  # 'amdrocm10.0-gfx1201' now), so a hand-written list goes stale on the next
  # upgrade and silently leaves the previous runtime installed beside the new
  # one. Everything is reinstalled from the repositories registered below, so
  # removing all of it is the point rather than a side effect.
  local -a installed_packages=()
  mapfile -t installed_packages < <(
    dpkg-query -W -f='${db:Status-Status} ${Package}\n' 'amdgpu*' 'amdrocm*' 'rocm*' 2>/dev/null |
      awk '$1 != "not-installed" { print $2 }' | sort -u
  )

  if [[ "${#installed_packages[@]}" -gt 0 ]]; then
    apt-get purge -y "${installed_packages[@]}"
  fi

  apt-get autoremove -y

  # Repository lists and the o=repo.radeon.com pin that the purged
  # amdgpu-install package owns. Removed by hand as well because a host that
  # never had that package can still carry them from an earlier manual install,
  # and a stale rocmradeon entry keeps offering the old ROCm beside the new one.
  rm -f \
    /etc/apt/preferences.d/repo-radeon-pin-600 \
    /etc/apt/sources.list.d/amdgpu.list \
    /etc/apt/sources.list.d/rocm.list

  # 'apt-get clean' empties the package cache but keeps the directories apt owns.
  # 'rm -rf /var/cache/apt/*' used to be here: it also deleted archives/partial/,
  # which apt-get recreates on an install but NOT on 'apt-get update', so the
  # breakage stayed invisible until the next download-only fetcher (notably
  # 'do-release-upgrade') failed every fetch with ENOENT.
  apt-get clean
  apt-get update

  panther_log_info 'Registering the AMD GPU driver and ROCm repositories...'

  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings

  # Two separate signing keys: repo.radeon.com signs the driver repository with
  # the ROCm key, stable.repo.amd.com signs ROCm 10 with a key of its own. Both
  # are served armored, hence the dearmor; '--yes' because re-running the step
  # would otherwise abort on the existing keyring.
  curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key |
    gpg --dearmor --yes -o /etc/apt/keyrings/rocm.gpg
  curl -fsSL https://stable.repo.amd.com/rocm/gpg/packages.gpg |
    gpg --dearmor --yes -o /etc/apt/keyrings/amdrocm.gpg
  chmod a+r /etc/apt/keyrings/rocm.gpg /etc/apt/keyrings/amdrocm.gpg

  tee /etc/apt/sources.list.d/amdgpu.sources <<EOF
Types: deb
URIs: https://repo.radeon.com/amdgpu/${amdgpu_release}/ubuntu
Suites: ${ubuntu_codename}
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/rocm.gpg
EOF

  tee /etc/apt/sources.list.d/amdrocm-stable.sources <<EOF
Types: deb
URIs: https://stable.repo.amd.com/rocm/core/packages/${rocm_distro}/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/amdrocm.gpg
EOF

  apt-get update

  panther_log_info "Installing AMD GPU driver ${amdgpu_release} & ROCm ${rocm_release} for ${rocm_arch}..."

  # amdgpu-dkms depends on dkms and amdgpu-dkms-firmware, so neither is
  # requested explicitly. The kernel headers DKMS builds against are not a
  # dependency of it: they come from Ubuntu's linux-headers-generic, which
  # linux-generic keeps in step with the installed kernels.
  apt-get install -y amdgpu-dkms "amdrocm${rocm_release}-${rocm_arch}"

  usermod -a -G render,video "$PANTHER_ALLOWED_USER"

  # DKMS rebuilds the module for every installed kernel, so several builds is
  # mechanically expected rather than a fault. What is not benign is what those
  # extra kernels imply: an in-place release upgrade keeps the previous
  # release's kernels, and that residue is what silently cost throughput after the
  # 26.04 upgrade here - every build succeeded, the module loaded, nothing failed,
  # and only a clean install restored performance. None of that state is visible
  # unless it is printed, so the parts that decide whether the GPU performs are
  # reported: which kernel has a module, which driver version is loaded versus
  # built, which firmware is installed, and which kernels are left over.
  local running_kernel newest_kernel target_kernel
  running_kernel="$(uname -r)"
  newest_kernel=''

  if compgen -G '/boot/vmlinuz-*' >/dev/null; then
    newest_kernel="$(printf '%s\n' /boot/vmlinuz-* | sed 's|.*/vmlinuz-||' | sort -V | tail -1)"
  fi

  target_kernel="${newest_kernel:-$running_kernel}"
  panther_log_info "Kernel running: ${running_kernel}; newest installed: ${newest_kernel:-unknown}"

  if [[ -n "$newest_kernel" && "$newest_kernel" != "$running_kernel" ]]; then
    panther_log_warn "Running ${running_kernel} while ${newest_kernel} is installed."
    panther_register_action "Reboot into ${newest_kernel}: ROCm on the older kernel's amdgpu/KFD loses performance silently instead of failing."
  fi

  if dkms status amdgpu 2>/dev/null | grep -q "$target_kernel"; then
    panther_log_success "amdgpu DKMS module built for ${target_kernel}."
  else
    panther_log_warn "No amdgpu DKMS module for ${target_kernel}; the in-tree driver would be used instead."
  fi

  local built_version loaded_version firmware_version
  built_version="$(dkms status amdgpu 2>/dev/null | awk -F'[/,]' -v kernel="$target_kernel" '$0 ~ kernel { gsub(/^ +| +$/, "", $2); print $2; exit }' || true)"
  loaded_version="$(modinfo -F version amdgpu 2>/dev/null || true)"
  firmware_version="$(dpkg-query -W -f='${Version}' amdgpu-dkms-firmware 2>/dev/null || true)"

  panther_log_info "amdgpu firmware: ${firmware_version:-not installed}"

  # Stale firmware degrades clocks and power management without ever failing, so
  # an absent package is worth saying out loud rather than leaving to inference.
  if [[ -z "$firmware_version" ]]; then
    panther_log_warn 'No amdgpu-dkms-firmware package; the GPU falls back to whatever linux-firmware ships.'
  fi

  if [[ -n "$loaded_version" && -n "$built_version" && "$loaded_version" != "$built_version" ]]; then
    panther_log_warn "Loaded amdgpu ${loaded_version} differs from the ${built_version} module built for ${target_kernel}; the running driver stays stale until reboot."
  fi

  # Kernel field, not the driver version: '7.0.0-30-generic' carries a hyphen
  # after the patch level, '6.19.14.31400100' does not. Matches both the
  # 'amdgpu/VERSION, KERNEL' and older 'amdgpu, VERSION, KERNEL' dkms formats.
  local -a leftover_kernels=()
  local dkms_line dkms_kernel
  while IFS= read -r dkms_line; do
    dkms_kernel="$(awk -F', *' '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+-/) { print $i; exit } }' <<<"$dkms_line" || true)"
    if [[ -n "$dkms_kernel" && "$dkms_kernel" != "$target_kernel" ]]; then
      leftover_kernels+=("$dkms_kernel")
    fi
  done < <(dkms status amdgpu 2>/dev/null || true)

  if [[ "${#leftover_kernels[@]}" -gt 0 ]]; then
    local leftovers
    leftovers="$(printf '%s\n' "${leftover_kernels[@]}" | sort -u -V | tr '\n' ' ' | sed 's/ *$//')"
    panther_log_warn "Modules also built for kernels other than ${target_kernel}: ${leftovers}"
    panther_register_action "Confirm 'modinfo amdgpu | head -3' reports ${built_version:-the new version} after reboot: leftover kernels mean this host was upgraded in place, where a stale driver degrades throughput silently instead of failing."
  fi

  panther_register_action 'Reboot the server to load the new amdgpu kernel driver.'
  panther_log_success 'AMD GPU and ROCm installed.'
}

panther_setup_amdgpu
