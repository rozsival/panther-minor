panther_t2i_remove() {
  local model="${args[model]}"
  panther_assert_supported_t2i "$model"

  local target_dir
  target_dir="$PANTHER_MODELS_DIR/t2i/.huggingface/$model"

  if [[ ! -d "$target_dir" ]]; then
    panther_log_error "Text-to-image model '$model' not found in local directory"
  fi

  read -r -p "Remove text-to-image model '$model'? (y/n) " -n 1 reply
  echo ''
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    panther_log_warn 'Removal aborted.'
    exit 0
  fi

  rm -rf "$target_dir"
  panther_log_success "Text-to-image model '$model' removed."
}

panther_t2i_remove
