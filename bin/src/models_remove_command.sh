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

panther_models_remove
