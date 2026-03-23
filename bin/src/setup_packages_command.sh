panther_setup_packages() {
  panther_prepare_setup_step 'Install essential packages.'

  panther_log_info 'Updating system and installing essential packages...'
  apt update
  apt upgrade -y
  apt install -y \
    augeas-lenses \
    augeas-tools \
    build-essential \
    htop \
    jq \
    nvtop \
    python3-full \
    python3-pip \
    tree \
    unattended-upgrades \
    unzip

  panther_log_success 'Essential packages installed.'
}

panther_setup_packages
