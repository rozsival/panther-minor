panther_setup_docker() {
  panther_prepare_setup_step 'Install Docker and Docker Compose.'

  panther_log_info 'Installing Docker and Docker Compose...'
  apt-get update
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  # shellcheck source=/dev/null # the host's file, read at runtime
  tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  apt-get update

  apt-get install -y \
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

  # llama-cpp runs in this slice (cgroup_parent in docker-compose.yml). 96G covers Qwen3.8-Flash-Next's host-resident
  # weights (~86 GiB: 40 expert blocks + the n-gram table) plus LLAMA_CPP_CACHE_RAM; see docs/llm.md#host-memory-protection.
  tee /etc/systemd/system/llm.slice <<EOF
[Unit]
Description=panther-minor llama.cpp (memory-protected)

[Slice]
MemoryLow=96G
EOF
  systemctl daemon-reload
  panther_log_success 'llm.slice memory protection configured.'
}

panther_setup_docker
