panther_t2i_config_file() {
  printf '%s\n' "$PANTHER_MODELS_DIR/t2i.config.json"
}
panther_supported_t2i() {
  jq -r '.models[] | .name' "$(panther_t2i_config_file)"
}
panther_assert_supported_t2i() {
  local model="$1"
  if jq -e --arg model "$model" '.models[] | select(.name == $model)' "$(panther_t2i_config_file)" >/dev/null; then
    return 0
  fi

  local supported_models
  supported_models="$(jq -r '[.models[].name] | join(", ")' "$(panther_t2i_config_file)")"
  panther_log_error "Unsupported text-to-image model '$model'. Supported models: $supported_models"
}
panther_t2i_config() {
  local model="$1"
  jq -r --arg model "$model" '.models[] | select(.name == $model)' "$(panther_t2i_config_file)"
}
# Hub-relative path (<repository>/<file>) of a model's component by role.
panther_t2i_component_path() {
  local model="$1" role="$2"
  panther_t2i_config "$model" | jq -r --arg role "$role" 'first(.components[] | select(.role == $role) | .repository + "/" + .file) // ""'
}
# Hub-relative paths of every component file the given model needs.
panther_t2i_model_files() {
  local model="$1"
  panther_t2i_config "$model" | jq -r '.components[] | .repository + "/" + .file'
}
panther_t2i_args() {
  local model="$1"
  panther_t2i_config "$model" | jq -r '(.args // []) | join(" ")'
}
