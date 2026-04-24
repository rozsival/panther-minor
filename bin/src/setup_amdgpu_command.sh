panther_setup_amdgpu() {
  panther_prepare_setup_step 'Install AMD GPU kernel drivers and ROCm.'

  panther_log_info 'Installing AMD GPU & ROCm...'

  apt autoremove -y amdgpu-dkms rocm rocm-core || true
  apt purge amdgpu-install
  apt autoremove

  rm -rf /var/cache/apt/*
  apt clean all
  apt update

  wget https://repo.radeon.com/amdgpu-install/7.2.2/ubuntu/noble/amdgpu-install_7.2.2.70202-1_all.deb
  apt install ./amdgpu-install_7.2.2.70202-1_all.deb
  sed -i "s|graphics/7.2.2|graphics/7.2.1|" /etc/apt/sources.list.d/rocm.list
  apt update

  apt install "linux-headers-$(uname -r)"
  apt install amdgpu-dkms -y
  apt install python3-setuptools python3-wheel -y
  usermod -a -G render,video "$LOGNAME"
  apt install rocm -y
  panther_log_success 'AMD GPU and ROCm installed.'
}

panther_setup_amdgpu
