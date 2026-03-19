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
