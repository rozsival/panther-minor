validate_supported_model() {
  local config_file="$PANTHER_MODELS_DIR/config.json"
  if [[ ! -f "$config_file" ]]; then
    echo "models config file not found: $config_file"
    return
  fi

  if jq -e --arg model "$1" '.models[] | select(.name == $model)' "$config_file" >/dev/null; then
    return 0
  fi

  local supported_models
  supported_models="$(jq -r '[.models[].name] | join(", ")' "$config_file")"
  echo "must be one of: $supported_models"
}
