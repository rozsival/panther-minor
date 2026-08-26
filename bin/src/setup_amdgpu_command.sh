panther_setup_amdgpu() {
  panther_prepare_setup_step 'Install AMD GPU kernel drivers and ROCm.'

  # AMD ships one amdgpu-install package per Ubuntu release. 31.40.1 is the
  # amdgpu driver + ROCm 7.14 bundle for Ubuntu 26.04 ('resolute'). The .deb only
  # registers the amdgpu and ROCm apt repositories; amdgpu-install does the work.
  local installer_version='31.40.1'
  local installer_package='amdgpu-install_31.40.1.314001-1_all.deb'

  # amdgpu-install appends this to the amdrocm meta package to pull the
  # arch-specific runtime. It is pinned instead of using '--gfxversion=auto'
  # because auto-detection aborts as soon as it sees more than one distinct gfx
  # target, which a Ryzen iGPU alongside the discrete cards would trigger.
  local rocm_arch="${ROCM_ARCH:-gfx1201}"
  local package

  panther_log_info 'Removing any previous AMD GPU & ROCm installation...'

  # Purged one at a time: apt-get fails the whole transaction when a single name
  # is unknown, and which of these exist depends on the ROCm version installed
  # before (7.2 and older used 'rocm'/'rocm-core', 7.14 uses 'amdrocm').
  for package in amdgpu-dkms amdrocm rocm rocm-core; do
    apt-get autoremove -y "$package" || true
  done

  apt-get purge -y amdgpu-install || true
  apt-get autoremove -y

  # 'apt-get clean' empties the package cache but keeps the directories apt owns.
  # 'rm -rf /var/cache/apt/*' used to be here: it also deleted archives/partial/,
  # which apt-get recreates on an install but NOT on 'apt-get update', so the
  # breakage stayed invisible until the next download-only fetcher (notably
  # 'do-release-upgrade') failed every fetch with ENOENT.
  apt-get clean
  apt-get update

  panther_log_info "Installing AMD GPU & ROCm for ${rocm_arch}..."

  if [ ! -d ./temp ]; then
    mkdir ./temp
  fi

  wget "https://repo.radeon.com/amdgpu-install/${installer_version}/ubuntu/resolute/${installer_package}" -O "./temp/${installer_package}"
  apt-get install -y "./temp/${installer_package}"
  apt-get update
  rm "./temp/${installer_package}"

  usermod -a -G render,video "$PANTHER_ALLOWED_USER"

  # 'rocm,graphics' is the mixed compute + graphics use case for this host.
  # amdgpu-install pulls in amdgpu-dkms plus the matching linux-headers for every
  # installed kernel on its own, so neither is requested explicitly above.
  amdgpu-install -y --usecase=rocm,graphics --gfxversion="$rocm_arch"

  # amdgpu-install builds the DKMS module for every installed kernel, so several
  # builds is mechanically expected rather than a fault. What is not benign is
  # what those extra kernels imply: an in-place release upgrade keeps the previous
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
