panther_setup_packages() {
  panther_prepare_setup_step 'Install essential packages.'

  panther_log_info 'Updating system and installing essential packages...'
  apt-get update
  # '--with-new-pkgs' is what makes this equivalent to 'apt upgrade': plain
  # 'apt-get upgrade' holds back any upgrade that needs a new package, which is
  # exactly what a kernel ABI bump is (linux-generic pulling a new linux-image).
  apt-get upgrade -y --with-new-pkgs
  apt-get install -y \
    augeas-lenses \
    augeas-tools \
    bind9-dnsutils \
    build-essential \
    htop \
    jq \
    lm-sensors \
    nvtop \
    python3 \
    python3-pip \
    python3-venv \
    s-tui \
    tree \
    unattended-upgrades \
    unzip

  panther_log_success 'Essential packages installed.'
}

panther_setup_packages
