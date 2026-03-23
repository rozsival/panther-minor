panther_models_config_file() {
  printf '%s\n' "$PANTHER_MODELS_DIR/config.json"
}
panther_supported_models() {
  jq -r '.models[] | .name + (if .thinking == true then " (thinking)" else "" end)' "$(panther_models_config_file)"
}
panther_assert_supported_model() {
  local model="$1"
  if jq -e --arg model "$model" '.models[] | select(.name == $model)' "$(panther_models_config_file)" >/dev/null; then
    return 0
  fi

  local supported_models
  supported_models="$(jq -r '[.models[].name] | join(", ")' "$(panther_models_config_file)")"
  panther_log_error "Unsupported model '$model'. Supported models: $supported_models"
}
panther_load_dotenv() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0

  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key%%[[:space:]]*}"
    [[ -n "$key" ]] || continue
    if ! [[ -v $key ]]; then
      export "$key=$value"
    fi
  done <"$env_file"
}
panther_model_config() {
  local model="$1"
  jq -r --arg model "$model" '.models[] | select(.name == $model)' "$(panther_models_config_file)"
}
