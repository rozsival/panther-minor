panther_setup_amdgpu() {
  panther_prepare_setup_step 'Install AMD GPU kernel drivers and ROCm.'

  panther_log_info 'Installing AMD GPU & ROCm...'

  apt autoremove -y amdgpu-dkms rocm rocm-core || true
  apt purge -y amdgpu-install || true
  apt autoremove

  rm -rf /var/cache/apt/*
  apt clean all
  apt update

  if [ ! -d ./temp ]; then
    mkdir ./temp
  fi

  wget https://repo.radeon.com/amdgpu-install/7.2.4/ubuntu/noble/amdgpu-install_7.2.4.70204-1_all.deb -O ./temp/amdgpu-install_7.2.4.70204-1_all.deb
  apt install -y ./temp/amdgpu-install_7.2.4.70204-1_all.deb
  apt update
  rm ./temp/amdgpu-install_7.2.4.70204-1_all.deb

  apt install -y "linux-headers-$(uname -r)" amdgpu-dkms python3-setuptools python3-wheel
  usermod -a -G render,video "$PANTHER_ALLOWED_USER"
  apt install -y rocm
  panther_log_success 'AMD GPU and ROCm installed.'
}

panther_setup_amdgpu
