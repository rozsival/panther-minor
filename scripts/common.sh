#!/usr/bin/env bash

# -- Config -------------------------------------------------------------------
SERVER_NAME=$HOSTNAME
ALLOWED_USER=$USER
SSH_PORT=2222
SSHD_CONFIG=/etc/ssh/sshd_config
FAIL2BAN_JAIL=/etc/fail2ban/jail.local

# -- Color helpers -----------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# -- Guards -------------------------------------------------------------------
require_root() {
	[[ $EUID -eq 0 ]] || log_error "This script must be run as root (use sudo)."
}

# Prompt for confirmation unless already confirmed by a parent (e.g. setup.sh).
# Usage: confirm "Description of what is about to run"
confirm() {
	[[ "${PANTHER_CONFIRMED:-0}" == "1" ]] && return 0
	local msg="${1:-Are you sure you want to continue?}"
	echo -e "${YELLOW}[CONFIRM]${NC} $msg"
	read -r -p "         Proceed? (y/N): " _reply
	[[ "$_reply" =~ ^[Yy]$ ]] || { log_warn "Aborted."; exit 0; }
}

# -- Deferred Actions ---------------------------------------------------------
# A file to store actions that need user attention at the end
ACTIONS_FILE="/tmp/${SERVER_NAME}_actions"
[[ -f "$ACTIONS_FILE" ]] || touch "$ACTIONS_FILE"

register_action() {
	echo "$*" >> "$ACTIONS_FILE"
}

# -- Bashrc Helpers -----------------------------------------------------------
register_bashrc_entry() {
	local label="$1"
	local cmd="$2"
	local user="${3:-$ALLOWED_USER}"
	local bashrc="/home/$user/.bashrc"

	if ! grep -qF "$cmd" "$bashrc"; then
		log_info "Adding $label to $bashrc..."
		echo -e "\n# $label\n$cmd" >> "$bashrc"
		chown "$user:$user" "$bashrc"
	fi
}

# -- Env Helpers --------------------------------------------------------------
detect_group_gid() {
	local group_name="$1"
	getent group "$group_name" | awk -F: '{print $3}'
}

upsert_env_key() {
	local env_file="$1"
	local key="$2"
	local value="$3"

	if command -v augtool >/dev/null 2>&1; then
		# Use Augeas Shellvars lens for idempotent updates.
		augtool -A -L <<EOF
set /files${env_file}/${key} "${value}"
save
EOF
		return 0
	fi

	# Fallback for environments without augtool.
	if grep -qE "^${key}=" "$env_file"; then
		sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
	else
		printf '%s=%s\n' "$key" "$value" >> "$env_file"
	fi
}

sync_env_gpu_gids() {
	local env_file="$1"
	[[ -f "$env_file" ]] || log_error "Missing env file: $env_file"

	local video_gid render_gid
	video_gid="$(detect_group_gid video || true)"
	render_gid="$(detect_group_gid render || true)"

	[[ -n "$video_gid" ]] || log_error "Could not detect 'video' group GID"
	[[ -n "$render_gid" ]] || log_error "Could not detect 'render' group GID"

	upsert_env_key "$env_file" "VIDEO_GID" "$video_gid"
	upsert_env_key "$env_file" "RENDER_GID" "$render_gid"
}

