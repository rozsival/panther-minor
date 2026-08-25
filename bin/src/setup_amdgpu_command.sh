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

  # Purged one at a time: apt fails the whole transaction when a single name is
  # unknown, and which of these exist depends on the ROCm version installed
  # before (7.2 and older used 'rocm'/'rocm-core', 7.14 uses 'amdrocm').
  for package in amdgpu-dkms amdrocm rocm rocm-core; do
    apt autoremove -y "$package" || true
  done

  apt purge -y amdgpu-install || true
  apt autoremove -y

  rm -rf /var/cache/apt/*
  apt clean all
  apt update

  panther_log_info "Installing AMD GPU & ROCm for ${rocm_arch}..."

  if [ ! -d ./temp ]; then
    mkdir ./temp
  fi

  wget "https://repo.radeon.com/amdgpu-install/${installer_version}/ubuntu/resolute/${installer_package}" -O "./temp/${installer_package}"
  apt install -y "./temp/${installer_package}"
  apt update
  rm "./temp/${installer_package}"

  usermod -a -G render,video "$PANTHER_ALLOWED_USER"

  # 'rocm,graphics' is the mixed compute + graphics use case for this host.
  # amdgpu-install pulls in amdgpu-dkms plus the matching linux-headers for every
  # installed kernel on its own, so neither is requested explicitly above.
  amdgpu-install -y --usecase=rocm,graphics --gfxversion="$rocm_arch"

  panther_register_action 'Reboot the server to load the new amdgpu kernel driver.'
  panther_log_success 'AMD GPU and ROCm installed.'
}

panther_setup_amdgpu
