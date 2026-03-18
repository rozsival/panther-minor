panther_log_info() {
	echo -e "\033[0;34m[INFO]\033[0m  $*"
}

panther_log_success() {
	echo -e "\033[0;32m[OK]\033[0m    $*"
}

panther_log_warn() {
	echo -e "\033[1;33m[WARN]\033[0m  $*"
}

panther_log_error() {
	echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
	exit 1
}

panther_resolve_option() {
	local flag_name="$1"
	local env_name="$2"
	local default_value="${3:-}"

	if [[ -n ${args[$flag_name]+x} && -n ${args[$flag_name]} ]]; then
		printf '%s\n' "${args[$flag_name]}"
		return 0
	fi

	if [[ -v $env_name ]]; then
		printf '%s\n' "$(printenv "$env_name")"
		return 0
	fi

	printf '%s\n' "$default_value"
}

panther_resolve_setup_context() {
	declare -g PANTHER_SERVER_NAME
	declare -g PANTHER_ALLOWED_USER
	declare -g PANTHER_SSH_PORT
	declare -g PANTHER_TIMEZONE
	declare -g PANTHER_LVM_DEVICE
	declare -g PANTHER_ACTIONS_FILE

	PANTHER_SERVER_NAME="$(panther_resolve_option '--server-name' PANTHER_SERVER_NAME "$HOSTNAME")"
	PANTHER_ALLOWED_USER="$(panther_resolve_option '--allowed-user' PANTHER_ALLOWED_USER "$USER")"
	PANTHER_SSH_PORT="$(panther_resolve_option '--ssh-port' PANTHER_SSH_PORT '2222')"
	PANTHER_TIMEZONE="$(panther_resolve_option '--timezone' PANTHER_TIMEZONE 'Europe/Prague')"
	PANTHER_LVM_DEVICE="$(panther_resolve_option '--lvm-device' PANTHER_LVM_DEVICE '/dev/ubuntu-vg/ubuntu-lv')"
	PANTHER_ACTIONS_FILE="/tmp/${PANTHER_SERVER_NAME}_actions"
}

panther_require_root() {
	[[ $EUID -eq 0 ]] || panther_log_error "This command must be run as root (use sudo)."
}

panther_confirm() {
	[[ "${PANTHER_CONFIRMED:-0}" == "1" ]] && return 0
	local message="${1:-Are you sure you want to continue?}"
	echo -e "\033[1;33m[CONFIRM]\033[0m $message"
	read -r -p "         Proceed? (y/N): " reply
	[[ "$reply" =~ ^[Yy]$ ]] || {
		panther_log_warn "Aborted."
		exit 0
	}
}

panther_ensure_actions_file() {
	mkdir -p "$(dirname "$PANTHER_ACTIONS_FILE")"
	[[ -f "$PANTHER_ACTIONS_FILE" ]] || touch "$PANTHER_ACTIONS_FILE"
}

panther_register_action() {
	panther_ensure_actions_file
	printf '%s\n' "$*" >> "$PANTHER_ACTIONS_FILE"
}

panther_register_bashrc_entry() {
	local label="$1"
	local command="$2"
	local user_name="${3:-$PANTHER_ALLOWED_USER}"
	local bashrc="/home/$user_name/.bashrc"

	if ! grep -qF "$command" "$bashrc"; then
		panther_log_info "Adding $label to $bashrc..."
		printf '\n# %s\n%s\n' "$label" "$command" >> "$bashrc"
		chown "$user_name:$user_name" "$bashrc"
	fi
}

panther_detect_group_gid() {
	local group_name="$1"
	getent group "$group_name" | awk -F: '{print $3}'
}

panther_upsert_env_key() {
	local env_file="$1"
	local key="$2"
	local value="$3"

	if command -v augtool >/dev/null 2>&1; then
		augtool -A -L <<AUGEOF
set /files${env_file}/${key} "${value}"
save
AUGEOF
		return 0
	fi

	if grep -qE "^${key}=" "$env_file"; then
		sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
	else
		printf '%s=%s\n' "$key" "$value" >> "$env_file"
	fi
}

panther_sync_env_gpu_gids() {
	local env_file="$1"
	[[ -f "$env_file" ]] || panther_log_error "Missing env file: $env_file"

	local video_gid render_gid
	video_gid="$(panther_detect_group_gid video || true)"
	render_gid="$(panther_detect_group_gid render || true)"

	[[ -n "$video_gid" ]] || panther_log_error "Could not detect 'video' group GID"
	[[ -n "$render_gid" ]] || panther_log_error "Could not detect 'render' group GID"

	panther_upsert_env_key "$env_file" VIDEO_GID "$video_gid"
	panther_upsert_env_key "$env_file" RENDER_GID "$render_gid"
}

panther_prepare_setup_step() {
	local message="$1"
	panther_resolve_setup_context
	panther_require_root
	panther_confirm "$message"
	panther_ensure_actions_file
}

panther_print_setup_summary() {
	echo ''
	echo -e "\033[0;32m╔══════════════════════════════════════════════╗\033[0m"
	echo -e "\033[0;32m║  🐆 ${PANTHER_SERVER_NAME} setup complete!            ║\033[0m"
	echo -e "\033[0;32m╠══════════════════════════════════════════════╣\033[0m"
	printf "\033[0;32m║  0. Init     : %-30s║\033[0m\n" "complete"
	printf "\033[0;32m║  1. Packages : %-30s║\033[0m\n" "installed"
	printf "\033[0;32m║  2. Brew     : %-30s║\033[0m\n" "ready"
	printf "\033[0;32m║  3. Docker   : %-30s║\033[0m\n" "ready"
	printf "\033[0;32m║  4. Tailscale: %-30s║\033[0m\n" "installed"
	printf "\033[0;32m║  5. SSH      : %-30s║\033[0m\n" "secured"
	printf "\033[0;32m║  6. UFW      : %-30s║\033[0m\n" "active"
	printf "\033[0;32m║  7. fail2ban : %-30s║\033[0m\n" "active"
	printf "\033[0;32m║  8. AMD GPU  : %-30s║\033[0m\n" "installed"
	printf "\033[0;32m║  9. GRUB     : %-30s║\033[0m\n" "configured"
	printf "\033[0;32m║ 10. Git      : %-30s║\033[0m\n" "configured"
	printf "\033[0;32m║ 11. Shell    : %-30s║\033[0m\n" "configured"
	printf "\033[0;32m║ 12. Env      : %-30s║\033[0m\n" "synced"
	echo -e "\033[0;32m╚══════════════════════════════════════════════╝\033[0m"

	if [[ -s "$PANTHER_ACTIONS_FILE" ]]; then
		echo ''
		panther_log_warn '⚠  ACTIONS REQUIRED TO FINISH SETUP:'
		while IFS= read -r line; do
			echo -e "   \033[1;33m•\033[0m $line"
		done < "$PANTHER_ACTIONS_FILE"
	fi

	echo ''
	panther_log_info "Reconnection: ssh -p ${PANTHER_SSH_PORT} ${PANTHER_ALLOWED_USER}@<server-ip>"
}

panther_setup_init() {
	panther_prepare_setup_step 'Extend LVM logical volume to full disk capacity.'

	panther_log_info 'Extending LVM logical volume to full disk capacity...'
	lvextend -An -l +100%FREE "$PANTHER_LVM_DEVICE"
	resize2fs "$PANTHER_LVM_DEVICE"
	panther_log_success 'Disk fully allocated.'

	panther_log_info "Setting up server timezone to ${PANTHER_TIMEZONE}..."
	timedatectl set-timezone "$PANTHER_TIMEZONE"
	panther_log_success "Timezone set to ${PANTHER_TIMEZONE}."
}

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

panther_setup_brew() {
	panther_prepare_setup_step 'Install Homebrew and LLMFit.'

	panther_log_info "Installing Homebrew (as ${PANTHER_ALLOWED_USER})..."
	mkdir -p /home/linuxbrew/.linuxbrew
	chown -R "${PANTHER_ALLOWED_USER}:${PANTHER_ALLOWED_USER}" /home/linuxbrew

	sudo -u "${PANTHER_ALLOWED_USER}" bash -c 'NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

	local brew_prefix
	brew_prefix=$(sudo -u "${PANTHER_ALLOWED_USER}" bash -c '
		if [ -d ~/.linuxbrew ]; then
			echo "$HOME/.linuxbrew"
		elif [ -d /home/linuxbrew/.linuxbrew ]; then
			echo "/home/linuxbrew/.linuxbrew"
		fi
	')

	if [[ -n "$brew_prefix" ]]; then
		panther_register_bashrc_entry 'Homebrew' "eval \"\$(${brew_prefix}/bin/brew shellenv)\""
		panther_log_success "Homebrew installed and configured for ${PANTHER_ALLOWED_USER}."

		eval "\$(${brew_prefix}/bin/brew shellenv)"

		panther_log_info 'Installing LLMFit via Homebrew...'
		sudo -u "${PANTHER_ALLOWED_USER}" bash -c "${brew_prefix}/bin/brew install llmfit"
		panther_log_success "LLMFit installed via Homebrew for user ${PANTHER_ALLOWED_USER}."

		panther_log_info 'Installing Hugging Face CLI via Homebrew...'
		sudo -u "${PANTHER_ALLOWED_USER}" bash -c "${brew_prefix}/bin/brew install huggingface-cli"
		panther_log_success "Hugging Face CLI installed via Homebrew for user ${PANTHER_ALLOWED_USER}."
	else
		panther_log_error 'Homebrew installation failed.'
	fi
}

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

panther_setup_tailscale() {
	panther_prepare_setup_step 'Install Tailscale.'

	panther_log_info 'Installing Tailscale...'
	curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$(. /etc/os-release && echo "$VERSION_CODENAME").noarmor.gpg" | tee /usr/share/keyrings/tailscale-archive-keyring.gpg
	curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$(. /etc/os-release && echo "$VERSION_CODENAME").tailscale-keyring.list" | tee /etc/apt/sources.list.d/tailscale.list

	apt update
	apt install -y tailscale

	if command -v tailscale >/dev/null 2>&1; then
		panther_log_success 'Tailscale installed.'
		panther_register_action "Authenticate Tailscale: run 'sudo tailscale up' from your workstation via SSH (GUI with browser needed)."
	else
		panther_log_error 'Tailscale installation failed.'
	fi
}

panther_setup_ssh() {
	panther_prepare_setup_step "Harden SSH configuration (port ${PANTHER_SSH_PORT}, key-only auth)."

	panther_log_info "Configuring SSH (${PANTHER_SSHD_CONFIG})..."

	if [[ ! -f "${PANTHER_SSHD_CONFIG}.orig" ]]; then
		cp "$PANTHER_SSHD_CONFIG" "${PANTHER_SSHD_CONFIG}.orig"
		panther_log_info "Original sshd_config backed up to ${PANTHER_SSHD_CONFIG}.orig"
	fi

	panther_log_info 'Applying SSH hardening via Augeas...'
	rm -f /etc/ssh/sshd_config.d/*.conf

	augtool -s <<AUGEOF
set /files/etc/ssh/sshd_config/Port "$PANTHER_SSH_PORT"
set /files/etc/ssh/sshd_config/PasswordAuthentication no
set /files/etc/ssh/sshd_config/KbdInteractiveAuthentication no
set /files/etc/ssh/sshd_config/ChallengeResponseAuthentication no
set /files/etc/ssh/sshd_config/PubkeyAuthentication yes
set /files/etc/ssh/sshd_config/AuthenticationMethods publickey
set /files/etc/ssh/sshd_config/UsePAM no
set /files/etc/ssh/sshd_config/PermitRootLogin no
set /files/etc/ssh/sshd_config/MaxAuthTries 3
set /files/etc/ssh/sshd_config/LoginGraceTime 30
set /files/etc/ssh/sshd_config/X11Forwarding no
set /files/etc/ssh/sshd_config/AllowTcpForwarding no
set /files/etc/ssh/sshd_config/AllowUsers/1 "$PANTHER_ALLOWED_USER"
AUGEOF

	panther_log_info 'Validating SSH configuration...'
	sshd -t || panther_log_error 'sshd configuration is invalid -- aborting to avoid locking you out.'

	panther_log_info 'Restarting SSH service...'
	systemctl restart ssh
	panther_log_success "SSH hardened on port ${PANTHER_SSH_PORT}. AllowUsers: ${PANTHER_ALLOWED_USER}"
}

panther_setup_ufw() {
	panther_prepare_setup_step 'Configure UFW firewall (reset and re-apply rules).'

	panther_log_info 'Configuring UFW...'
	ufw --force reset
	ufw default deny incoming
	ufw default allow outgoing

	ufw allow "${PANTHER_SSH_PORT}/tcp" comment 'SSH'
	ufw allow 80/tcp comment 'HTTP'
	ufw allow 443/tcp comment 'HTTPS'

	ufw --force enable

	panther_log_success "UFW enabled. Open ports: SSH(${PANTHER_SSH_PORT}), HTTP(80), HTTPS(443). AI/monitoring services accessible via localhost/Tailscale only."
}

panther_setup_fail2ban() {
	panther_prepare_setup_step 'Install and configure fail2ban.'

	panther_log_info 'Installing fail2ban...'
	apt install -y fail2ban

	panther_log_info "Writing ${PANTHER_FAIL2BAN_JAIL}..."
	cat > "$PANTHER_FAIL2BAN_JAIL" <<EOF
[sshd]
enabled  = true
port     = ${PANTHER_SSH_PORT}
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 1h
findtime = 10m
EOF

	panther_log_info 'Restarting fail2ban...'
	systemctl enable --now fail2ban
	systemctl restart fail2ban
	panther_log_success 'fail2ban configured and running.'
}

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

panther_setup_grub() {
	panther_prepare_setup_step 'Update GRUB kernel parameters.'

	panther_log_info 'Configuring GRUB kernel parameters...'
	local current_cmdline updated_cmdline
	current_cmdline="$(augtool -n get /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT | cut -d'=' -f2 | tr -d '"' | tr -d "'")"
	updated_cmdline="$current_cmdline"

	for param in amdgpu.mes=1 iommu=pt; do
		if [[ ! "$current_cmdline" =~ $param ]]; then
			updated_cmdline="$updated_cmdline $param"
		fi
	done

	updated_cmdline="$(echo "$updated_cmdline" | xargs)"

	if [[ "$current_cmdline" != "$updated_cmdline" ]]; then
		panther_log_info "Updating GRUB_CMDLINE_LINUX_DEFAULT to: $updated_cmdline"
		augtool -s <<AUGEOF
set /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT "'$updated_cmdline'"
AUGEOF
		panther_log_info 'Running update-grub...'
		update-grub
		panther_log_success 'GRUB configuration updated.'
	else
		panther_log_success 'GRUB kernel parameters already set.'
	fi
}

panther_setup_git() {
	panther_prepare_setup_step "Configure Git for ${PANTHER_ALLOWED_USER}."

	panther_log_info "Configuring Git for ${PANTHER_ALLOWED_USER}..."
	sudo -u "${PANTHER_ALLOWED_USER}" git config --global user.name "${PANTHER_SERVER_NAME}"
	sudo -u "${PANTHER_ALLOWED_USER}" git config --global user.email "${PANTHER_ALLOWED_USER}@${PANTHER_SERVER_NAME}"
	sudo -u "${PANTHER_ALLOWED_USER}" git config --global pull.rebase true
	sudo -u "${PANTHER_ALLOWED_USER}" git config --global credential.helper store
	panther_log_success "Git configured for ${PANTHER_ALLOWED_USER}."
}

panther_setup_shell() {
	panther_prepare_setup_step "Set up shell with Starship prompt for ${PANTHER_ALLOWED_USER}."

	panther_log_info "Setting up shell with Starship prompt for ${PANTHER_ALLOWED_USER}..."
	apt install -y starship

	usermod -aG video "$PANTHER_ALLOWED_USER"
	usermod -aG render "$PANTHER_ALLOWED_USER"
	loginctl enable-linger "$PANTHER_ALLOWED_USER"

	panther_register_bashrc_entry 'Starship' 'eval "$(starship init bash)"'
	panther_log_success "Shell set up with Starship prompt for ${PANTHER_ALLOWED_USER}."
}

panther_setup_env() {
	panther_prepare_setup_step 'Set up env vars and sync GPU group IDs.'

	if [[ ! -f "$PANTHER_ENV_FILE" ]]; then
		[[ -f "$PANTHER_ENV_EXAMPLE_FILE" ]] || panther_log_error "Missing $PANTHER_ENV_EXAMPLE_FILE"
		panther_log_info "Creating $PANTHER_ENV_FILE from .env.example..."
		cp "$PANTHER_ENV_EXAMPLE_FILE" "$PANTHER_ENV_FILE"
		chown "$PANTHER_ALLOWED_USER:$PANTHER_ALLOWED_USER" "$PANTHER_ENV_FILE"
	fi

	panther_log_info "Syncing VIDEO_GID and RENDER_GID in $PANTHER_ENV_FILE from host groups..."
	panther_sync_env_gpu_gids "$PANTHER_ENV_FILE"
	panther_log_success 'Env vars ready.'
}

panther_setup_all() {
	panther_resolve_setup_context
	panther_require_root
	panther_confirm "This will configure the full ${PANTHER_SERVER_NAME} workstation setup."

	: > "$PANTHER_ACTIONS_FILE"

	panther_log_info "🐆 ${PANTHER_SERVER_NAME} setup starting..."
	echo ''

	PANTHER_CONFIRMED=1 panther_setup_init
	PANTHER_CONFIRMED=1 panther_setup_packages
	PANTHER_CONFIRMED=1 panther_setup_brew
	PANTHER_CONFIRMED=1 panther_setup_docker
	PANTHER_CONFIRMED=1 panther_setup_tailscale
	PANTHER_CONFIRMED=1 panther_setup_ssh
	PANTHER_CONFIRMED=1 panther_setup_ufw
	PANTHER_CONFIRMED=1 panther_setup_fail2ban
	PANTHER_CONFIRMED=1 panther_setup_amdgpu
	PANTHER_CONFIRMED=1 panther_setup_grub
	PANTHER_CONFIRMED=1 panther_setup_git
	PANTHER_CONFIRMED=1 panther_setup_shell
	PANTHER_CONFIRMED=1 panther_setup_env

	panther_print_setup_summary
	rm -f "$PANTHER_ACTIONS_FILE"

	echo ''
	read -r -p 'System reboot is required to apply all changes. Reboot now? (y/N): ' reboot_reply
	if [[ "$reboot_reply" =~ ^[Yy]$ ]]; then
		panther_log_info 'Rebooting system in 5 seconds...'
		sleep 5
		reboot
	else
		panther_log_warn 'Reboot skipped. Please remember to reboot manually.'
		exec su - "$PANTHER_ALLOWED_USER"
	fi
}

panther_models_config_file() {
	printf '%s\n' "$PANTHER_MODELS_DIR/config.json"
}

panther_supported_models() {
	jq -r '.models[] | .name + (if .thinking == true then " (thinking)" else "" end)' "$(panther_models_config_file)"
}

panther_assert_supported_model() {
	local model="$1"
	if jq -e --arg model "$model" '.models[] | select(.name == $model)' "$(panther_models_config_file)" >/dev/null; then
		return 0
	fi

	local supported_models
	supported_models="$(jq -r '[.models[].name] | join(", ")' "$(panther_models_config_file)")"
	panther_log_error "Unsupported model '$model'. Supported models: $supported_models"
}

panther_load_dotenv() {
	local env_file="$1"
	[[ -f "$env_file" ]] || return 0

	local line key value
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
		key="${line%%=*}"
		value="${line#*=}"
		key="${key%%[[:space:]]*}"
		[[ -n "$key" ]] || continue
		if ! [[ -v $key ]]; then
			export "$key=$value"
		fi
	done < "$env_file"
}

panther_model_config() {
	local model="$1"
	jq -r --arg model "$model" '.models[] | select(.name == $model)' "$(panther_models_config_file)"
}

panther_models_download() {
	local model="${args[model]}"
	panther_assert_supported_model "$model"
	mkdir -p "$PANTHER_MODELS_DIR/.huggingface"
	panther_load_dotenv "$PANTHER_ENV_FILE"

	local model_config hf_repository hf_file model_name target_file
	model_config="$(panther_model_config "$model")"
	[[ -n "$model_config" ]] || panther_log_error "Model '$model' not found in $(panther_models_config_file)"

	hf_repository="$(jq -r '.repository' <<< "$model_config")"
	hf_file="$(jq -r '.file' <<< "$model_config")"
	model_name="$(jq -r '.name' <<< "$model_config")"
	target_file="$PANTHER_MODELS_DIR/.huggingface/$model_name.gguf"

	if [[ -f "$target_file" ]]; then
		read -r -p "Model '$model_name' already exists. Do you want to overwrite it? (y/n) " -n 1 reply
		echo ''
		if [[ ! "$reply" =~ ^[Yy]$ ]]; then
			panther_log_warn 'Download aborted.'
			exit 0
		fi
	fi

	hf download "$hf_repository" "$hf_file" --local-dir "$PANTHER_MODELS_DIR/.huggingface"
	mv -f "$PANTHER_MODELS_DIR/.huggingface/$hf_file" "$target_file"
	panther_log_success "Model '$model_name' ready for use."
}

panther_models_list() {
	echo 'Supported models:'
	while IFS= read -r model; do
		echo "- $model"
	done < <(panther_supported_models)
}

panther_models_remove() {
	local model="${args[model]}"
	panther_assert_supported_model "$model"

	local target_file="$PANTHER_MODELS_DIR/.huggingface/$model.gguf"
	if [[ ! -f "$target_file" ]]; then
		panther_log_error "Model '$model' not found in local directory"
	fi

	read -r -p "Remove model '$model'? (y/n) " -n 1 reply
	echo ''
	if [[ ! "$reply" =~ ^[Yy]$ ]]; then
		panther_log_warn 'Removal aborted.'
		exit 0
	fi

	rm "$target_file"
	panther_log_success "Model '$model' removed."
}

panther_compose() {
	(
		cd "$PANTHER_REPO_ROOT" || exit 1
		docker compose "$@"
	)
}

panther_cluster_start() {
	panther_log_info 'Starting cluster...'
	panther_compose up -d
	panther_log_success 'Cluster started.'
}

panther_cluster_stop() {
	local -a compose_args=(down)
	if [[ -n ${args[--volumes]+x} ]]; then
		compose_args+=(-v)
		panther_log_info 'Stopping cluster and removing volumes...'
	else
		panther_log_info 'Stopping cluster...'
	fi

	panther_compose "${compose_args[@]}"
	panther_log_success 'Cluster stopped.'
}

panther_cluster_cleanup() {
	panther_log_info 'Cleaning up cluster containers, volumes, images, and orphans...'
	panther_compose down -v --rmi all --remove-orphans
	panther_log_success 'Cluster cleanup completed.'
}

panther_cluster_restart() {
	panther_log_info 'Restarting cluster...'
	panther_compose down
	panther_compose up -d
	panther_log_success 'Cluster restarted.'
}

panther_cluster_build() {
	local -a compose_args=(build)
	if [[ -n ${args[--no-cache]+x} ]]; then
		compose_args+=(--no-cache)
		panther_log_info 'Building cluster images without cache...'
	else
		panther_log_info 'Building cluster images...'
	fi

	panther_compose "${compose_args[@]}"
	panther_log_success 'Cluster images built.'
}

panther_logs_service() {
	local service="$1"
	local -a compose_args=(logs -f)

	if [[ -n ${args[--tail]+x} ]]; then
		compose_args+=(--tail "${args[--tail]}")
		panther_log_info "Streaming logs for ${service} (last ${args[--tail]} lines)..."
	else
		panther_log_info "Streaming logs for ${service}..."
	fi

	compose_args+=("$service")
	panther_compose "${compose_args[@]}"
}

panther_logs_llama_cpp() {
	panther_logs_service 'llama-cpp'
}

panther_logs_llama_metrics_exporter() {
	panther_logs_service 'llama-metrics-exporter'
}

panther_logs_open_webui() {
	panther_logs_service 'open-webui'
}

panther_logs_prometheus() {
	panther_logs_service 'prometheus'
}

panther_logs_grafana() {
	panther_logs_service 'grafana'
}

panther_logs_node_exporter() {
	panther_logs_service 'node-exporter'
}

panther_logs_amd_gpu_exporter() {
	panther_logs_service 'amd-gpu-exporter'
}

panther_logs_proxy() {
	panther_logs_service 'proxy'
}

panther_update() {
	panther_log_info 'Fetching latest changes from upstream...'
	(
		cd "$PANTHER_REPO_ROOT" || exit 1
		git fetch --prune
		git pull --rebase
	)
	panther_log_success 'Repository updated.'
}

panther_proxy_certbot() {
	local domain="${args[--domain]}"
	local challenge_record="${args[--challenge-record]}"
	local credentials_file="$PANTHER_PROXY_DIR/acme/dns-credentials.json"
	local current_owner="$(id -u):$(id -g)"
	local force=false

	if ! mkdir -p "$PANTHER_PROXY_DIR/acme" "$PANTHER_PROXY_DIR/ssl"; then
		panther_log_error "Failed to create required directories under $PANTHER_PROXY_DIR"
	fi

	if [[ -n ${args[--force]+x} ]]; then
		read -r -p 'This will overwrite existing ACME DNS credentials. Are you sure? (y/n) ' -n 1 reply
		echo ''
		if [[ "$reply" =~ ^[Yy]$ ]]; then
			panther_log_info 'Forcing new acme-dns registration...'
			force=true
		else
			panther_log_info "Running without '--force'. Existing credentials will be used if available."
		fi
	fi

	local response username password fulldomain subdomain
	if [[ "$force" == true || ! -f "$credentials_file" ]]; then
		panther_log_info 'Registering with acme-dns...'
		response="$(curl -fsS -X POST https://auth.acme-dns.io/register)"
		[[ -n "$response" ]] || panther_log_error 'Empty response from acme-dns API.'

		username="$(echo "$response" | jq -r '.username')"
		password="$(echo "$response" | jq -r '.password')"
		fulldomain="$(echo "$response" | jq -r '.fulldomain')"
		subdomain="$(echo "$response" | jq -r '.subdomain')"

		if [[ "$username" == 'null' || -z "$username" ]]; then
			panther_log_error 'Failed to parse credentials.'
		fi

		printf '%s\n' "$response" > "$credentials_file"
		chmod 600 "$credentials_file"
		panther_log_success "Saved acme-dns credentials to $credentials_file."
	else
		panther_log_info "Using existing acme-dns credentials from $credentials_file."
		username="$(jq -r '.username' "$credentials_file")"
		password="$(jq -r '.password' "$credentials_file")"
		fulldomain="$(jq -r '.fulldomain' "$credentials_file")"
		subdomain="$(jq -r '.subdomain' "$credentials_file")"

		if [[ "$username" == 'null' || -z "$username" ]]; then
			panther_log_error "Invalid credentials file at $credentials_file. Run again with --force to register fresh acme-dns credentials."
		fi
	fi

	echo ''
	echo '=================================================================='
	echo 'ACTION REQUIRED: CREATE DNS CNAME RECORD'
	echo '=================================================================='
	echo "Record Name:  $challenge_record"
	echo 'Record Type:  CNAME'
	echo "Target:       $fulldomain"
	echo '=================================================================='
	echo ''
	read -r -p 'Press Enter to continue after DNS propagation...'

	panther_log_info 'Issuing certificate...'
	local issue_args=(--issue --dns dns_acmedns -d "$domain" --server letsencrypt)
	if [[ "$force" == true ]]; then
		issue_args+=(--force)
	fi

	docker run --rm -it \
		--user "$current_owner" \
		-v "$PANTHER_PROXY_DIR/acme:/acme.sh" \
		-e ACMEDNS_UPDATE_URL='https://auth.acme-dns.io/update' \
		-e ACMEDNS_USERNAME="$username" \
		-e ACMEDNS_PASSWORD="$password" \
		-e ACMEDNS_SUBDOMAIN="$subdomain" \
		neilpang/acme.sh "${issue_args[@]}"

	panther_log_info 'Installing certificate to SSL directory...'
	docker run --rm -it \
		--user "$current_owner" \
		-v "$PANTHER_PROXY_DIR/acme:/acme.sh" \
		-v "$PANTHER_PROXY_DIR/ssl:/ssl" \
		neilpang/acme.sh --install-cert -d "$domain" \
		--key-file /ssl/privkey.pem \
		--fullchain-file /ssl/fullchain.pem

	panther_log_info "Ensuring host file ownership for current user ($current_owner)..."
	docker run --rm \
		-v "$PANTHER_PROXY_DIR/acme:/acme.sh" \
		-v "$PANTHER_PROXY_DIR/ssl:/ssl" \
		alpine:3.22 sh -c "chown -R $current_owner /acme.sh /ssl"

	panther_log_success 'Certificate provisioning completed.'
}

panther_proxy_renew_ssl() {
	local current_owner="$(id -u):$(id -g)"
	mkdir -p "$PANTHER_PROXY_DIR/acme" "$PANTHER_PROXY_DIR/ssl"

	docker run --rm \
		--user "$current_owner" \
		-v "$PANTHER_PROXY_DIR/acme:/acme.sh" \
		-v "$PANTHER_PROXY_DIR/ssl:/ssl" \
		neilpang/acme.sh --cron

	cd "$PANTHER_REPO_ROOT" || exit 1
	docker compose exec proxy nginx -s reload
}

panther_proxy_setup_cron() {
	local schedule target_user log_path
	schedule="$(panther_resolve_option '--schedule' PANTHER_PROXY_SCHEDULE '0 2 * * *')"
	target_user="$(panther_resolve_option '--user' PANTHER_PROXY_USER "${SUDO_USER:-$USER}")"
	log_path="$(panther_resolve_option '--log-path' PANTHER_PROXY_LOG_PATH "$PANTHER_PROXY_DIR/renew-ssl.log")"

	[[ -f "$PANTHER_CLI_BIN" ]] || panther_log_error "CLI executable $PANTHER_CLI_BIN not found."

	local cron_command="cd '$PANTHER_REPO_ROOT' && '$PANTHER_CLI_BIN' proxy renew-ssl >> '$log_path' 2>&1"
	local cron_line="$schedule $cron_command"

	panther_log_info "Configuring SSL renewal cron for user '$target_user'."
	panther_log_info "Schedule: $schedule"
	panther_log_info "Command: $cron_command"
	panther_log_info "Log: $log_path"

	local -a crontab_list_cmd crontab_install_cmd
	if [[ $(id -u) -eq 0 ]]; then
		crontab_list_cmd=(crontab -u "$target_user" -l)
		crontab_install_cmd=(crontab -u "$target_user" -)
	else
		crontab_list_cmd=(crontab -l)
		crontab_install_cmd=(crontab -)
	fi

	if "${crontab_list_cmd[@]}" 2>/dev/null | grep -Fq "$cron_command"; then
		panther_log_success "Cron job already exists for user '$target_user'. No changes made."
		exit 0
	fi

	if ("${crontab_list_cmd[@]}" 2>/dev/null; echo "$cron_line") | "${crontab_install_cmd[@]}"; then
		panther_log_success "Cron job added for user '$target_user'."
	else
		panther_log_error "Failed to install cron job for user '$target_user'."
	fi

	if "${crontab_list_cmd[@]}" 2>/dev/null | grep -Fq "$cron_command"; then
		panther_log_success "Verified cron entry: $cron_line"
	else
		panther_log_error 'Cron installation could not be verified.'
	fi
}
