panther_setup_amdgpu() {
  panther_prepare_setup_step 'Install AMD GPU kernel drivers and ROCm.'

  panther_log_info 'Installing AMD GPU & ROCm...'
  mkdir --parents --mode=0755 /etc/apt/keyrings
  wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | gpg --dearmor | tee /etc/apt/keyrings/rocm.gpg

  apt autoremove -y amdgpu-dkms || true
  rm -f /etc/apt/sources.list.d/amdgpu.list
  rm -rf /var/cache/apt/*
  apt clean all
  apt update

  tee /etc/apt/sources.list.d/amdgpu.list <<EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/30.30/ubuntu noble main
EOF
  apt update
  apt install -y amdgpu-dkms

  tee /etc/apt/sources.list.d/rocm.list <<EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2 noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2/ubuntu noble main
EOF

  tee /etc/apt/preferences.d/rocm-pin-600 <<EOF
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

  apt update
  apt install -y rocm
  panther_log_success 'AMD GPU and ROCm installed.'
}

panther_setup_amdgpu
