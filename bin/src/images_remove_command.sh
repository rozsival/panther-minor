panther_images_remove() {
  local model="${args[model]}"
  panther_assert_supported_image "$model"

  local target_dir
  target_dir="$PANTHER_MODELS_DIR/.huggingface/$model"

  if [[ ! -d "$target_dir" ]]; then
    panther_log_error "Image model '$model' not found in local directory"
  fi

  read -r -p "Remove image model '$model'? (y/n) " -n 1 reply
  echo ''
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    panther_log_warn 'Removal aborted.'
    exit 0
  fi

  rm -rf "$target_dir"
  panther_log_success "Image model '$model' removed."
}

panther_images_remove
