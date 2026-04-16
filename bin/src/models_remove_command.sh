panther_models_remove() {
  local model="${args[model]}"
  panther_assert_supported_model "$model"

  local model_config model_name target_dir
  model_config="$(panther_model_config "$model")"

  [[ -n "$model_config" ]] || panther_log_error "Model '$model' not found in $(panther_models_config_file)"

  model_name="$(jq -r '.name' <<<"$model_config")"
  target_dir="$PANTHER_MODELS_DIR/.huggingface/$model_name"

  if [[ -d "$target_dir" ]]; then
    panther_log_error "Model '$model' not found in local directory"
  fi

  read -r -p "Remove model '$model'? (y/n) " -n 1 reply
  echo ''
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    panther_log_warn 'Removal aborted.'
    exit 0
  fi

  rm -rf "$target_dir"
  panther_log_success "Model '$model' removed."
}

panther_models_remove
