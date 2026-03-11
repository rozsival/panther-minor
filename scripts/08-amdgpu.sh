#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_root
confirm "Install AMD GPU kernel drivers and ROCm."

# =============================================================================
# 8. AMD GPU & ROCm
# =============================================================================
log_info "Installing AMD GPU & ROCm..."

# 1. Setup AMD packages signing key
mkdir --parents --mode=0755 /etc/apt/keyrings
wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
    gpg --dearmor | tee /etc/apt/keyrings/rocm.gpg

# 2. Clean up existing kernel drivers, repositories and cache
apt autoremove -y amdgpu-dkms || true
rm -f /etc/apt/sources.list.d/amdgpu.list
rm -rf /var/cache/apt/*
apt clean all
apt update

# 3. Register AMDGPU repository (using 'noble' as requested)
tee /etc/apt/sources.list.d/amdgpu.list << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/30.30/ubuntu noble main
EOF
apt update

# 4. Install AMDGPU DKMS
apt install -y amdgpu-dkms

# 5. Register ROCm package repository (using 'noble' as requested)
tee /etc/apt/sources.list.d/rocm.list << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2 noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2/ubuntu noble main
EOF

# 6. Set ROCm pin preferences
tee /etc/apt/preferences.d/rocm-pin-600 << EOF
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

apt update

# 7. Install ROCm
apt install -y rocm

log_success "AMD GPU and ROCm installed."

