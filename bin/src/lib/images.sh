panther_images_config_file() {
  printf '%s\n' "$PANTHER_MODELS_DIR/images.json"
}
panther_supported_images() {
  jq -r '.models[] | .name + (if .description then "  —  " + .description else "" end)' "$(panther_images_config_file)"
}
panther_assert_supported_image() {
  local model="$1"
  if jq -e --arg model "$model" '.models[] | select(.name == $model)' "$(panther_images_config_file)" >/dev/null; then
    return 0
  fi

  local supported_models
  supported_models="$(jq -r '[.models[].name] | join(", ")' "$(panther_images_config_file)")"
  panther_log_error "Unsupported image model '$model'. Supported models: $supported_models"
}
panther_image_config() {
  local model="$1"
  jq -r --arg model "$model" '.models[] | select(.name == $model)' "$(panther_images_config_file)"
}
