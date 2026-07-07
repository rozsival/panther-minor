panther_t2i_download() {
  local model="${args[model]}"
  panther_assert_supported_t2i "$model"
  panther_load_dotenv "$PANTHER_ENV_FILE"

  local model_config target_dir staging_dir
  model_config="$(panther_t2i_config "$model")"
  [[ -n "$model_config" ]] || panther_log_error "Text-to-image model '$model' not found in $(panther_t2i_config_file)"

  target_dir="$PANTHER_MODELS_DIR/t2i/.huggingface/$model"

  if [[ -f "$target_dir" ]]; then
    read -r -p "Model '$model' already exists. Do you want to overwrite it? (y/n) " -n 1 reply
    echo ''
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      panther_log_warn 'Download aborted.'
      exit 0
    else
      rm -rf "$target_dir"
    fi
  fi

  staging_dir="$target_dir/.staging"
  mkdir -p "$staging_dir"

  local components
  components="$(jq -c '.components[]' <<<"$model_config")"

  while IFS= read -r component; do
    local repository file target
    repository="$(jq -r '.repository' <<<"$component")"
    file="$(jq -r '.file' <<<"$component")"
    target="$(jq -r '.target' <<<"$component")"

    if [[ -f "$target_dir/$target" ]]; then
      panther_log_info "Skipping '$target' (already present)."
      continue
    fi

    panther_log_info "Downloading '$target' from '$repository'..."
    hf download "$repository" --include "$file" --local-dir "$staging_dir"
    mv "$staging_dir/$file" "$target_dir/$target"
  done <<<"$components"

  rm -rf "$staging_dir"
  panther_log_success "Text-to-image model '$model' ready for use."
}

panther_t2i_download
