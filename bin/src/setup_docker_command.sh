panther_setup_docker() {
  panther_prepare_setup_step 'Install Docker and Docker Compose.'

  panther_log_info 'Installing Docker and Docker Compose...'
  apt update
  apt install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  apt update

  apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  if docker --version && docker compose version; then
    panther_log_success 'Docker installed.'
  else
    panther_log_error 'Docker installation failed.'
  fi

  usermod -aG docker "${PANTHER_ALLOWED_USER}"
  panther_log_success 'User added to docker group.'
}

panther_setup_docker
