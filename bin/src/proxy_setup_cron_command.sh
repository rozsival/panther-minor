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

panther_proxy_setup_cron
