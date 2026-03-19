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

panther_models_download
