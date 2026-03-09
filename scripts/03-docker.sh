#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# =============================================================================
# 3. Docker & Docker Compose
# =============================================================================
log_info "Installing Docker and Docker Compose..."

# Add Docker's official GPG key:
apt update > /dev/null
apt install -y ca-certificates curl > /dev/null
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
tee /etc/apt/sources.list.d/docker.sources <<EOF > /dev/null
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt update > /dev/null

# Install the Docker packages:
apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin > /dev/null

# Verify installation
if docker --version >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  log_success "Docker installed."
else
  log_error "Docker installation failed."
fi

# Add user to the docker group
usermod -aG docker "${ALLOWED_USER}"
log_success "User added to docker group."
