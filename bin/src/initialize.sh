set -euo pipefail

declare -gr PANTHER_CLI_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cli"
declare -gr PANTHER_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
declare -gr PANTHER_MODELS_DIR="$PANTHER_REPO_ROOT/models"
declare -gr PANTHER_PROXY_DIR="$PANTHER_REPO_ROOT/proxy"
declare -gr PANTHER_ENV_FILE="$PANTHER_REPO_ROOT/.env"
declare -gr PANTHER_ENV_EXAMPLE_FILE="$PANTHER_REPO_ROOT/.env.example"
declare -gr PANTHER_SSHD_CONFIG="/etc/ssh/sshd_config"
declare -gr PANTHER_FAIL2BAN_JAIL="/etc/fail2ban/jail.local"

panther_is_logs_service() {
	case "${1:-}" in
	llama-cpp | llama-metrics-exporter | open-webui | prometheus | grafana | node-exporter | amd-gpu-exporter | proxy)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

panther_normalize_logs_tail_args() {
	[[ ${#command_line_args[@]} -ge 3 ]] || return 0
	[[ ${command_line_args[0]} == 'logs' ]] || return 0
	panther_is_logs_service "${command_line_args[1]}" || return 0

	local -a normalized_args=()
	local index=0

	while ((index < ${#command_line_args[@]})); do
		local current_arg="${command_line_args[$index]}"
		local next_arg="${command_line_args[$((index + 1))]:-}"

		normalized_args+=("$current_arg")

		if [[ $current_arg == '--tail' ]] && [[ -z $next_arg || $next_arg == -* ]]; then
			normalized_args+=('100')
		fi

		((index += 1))
	done

	command_line_args=("${normalized_args[@]}")
}

panther_normalize_logs_tail_args
