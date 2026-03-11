#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# =============================================================================
# 8. AMD GPU & ROCm
# =============================================================================
log_info "Installing AMD GPU & ROCm..."

# 1. Setup AMD packages signing key
mkdir --parents --mode=0755 /etc/apt/keyrings
wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
    gpg --dearmor | tee /etc/apt/keyrings/rocm.gpg > /dev/null

# 2. Clean up existing kernel drivers, repositories and cache
apt autoremove -y amdgpu-dkms > /dev/null 2>&1 || true
rm -f /etc/apt/sources.list.d/amdgpu.list
rm -rf /var/cache/apt/*
apt clean all > /dev/null
apt update > /dev/null

# 3. Register AMDGPU repository (using 'noble' as requested)
tee /etc/apt/sources.list.d/amdgpu.list << EOF > /dev/null
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/30.30/ubuntu noble main
EOF
apt update > /dev/null

# 4. Install AMDGPU DKMS
apt install -y amdgpu-dkms > /dev/null

# 5. Register ROCm package repository (using 'noble' as requested)
tee /etc/apt/sources.list.d/rocm.list << EOF > /dev/null
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2 noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2/ubuntu noble main
EOF

# 6. Set ROCm pin preferences
tee /etc/apt/preferences.d/rocm-pin-600 << EOF > /dev/null
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

apt update > /dev/null

# 7. Install ROCm
apt install -y rocm > /dev/null

log_success "AMD GPU and ROCm installed."

