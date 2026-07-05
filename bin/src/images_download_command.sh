panther_images_download() {
  local model="${args[model]}"
  panther_assert_supported_image "$model"
  panther_load_dotenv "$PANTHER_ENV_FILE"

  local model_config target_dir staging_dir
  model_config="$(panther_image_config "$model")"
  [[ -n "$model_config" ]] || panther_log_error "Image model '$model' not found in $(panther_images_config_file)"

  target_dir="$PANTHER_MODELS_DIR/.huggingface/$model"
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
  panther_log_success "Image model '$model' ready for use."
}

panther_images_download
