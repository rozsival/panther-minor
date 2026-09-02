panther_llm_config_file() {
  printf '%s\n' "$PANTHER_MODELS_DIR/llm.config.json"
}
panther_supported_llms() {
  jq -r '.models[].name' "$(panther_llm_config_file)"
}
panther_assert_supported_llm() {
  local model="$1"
  if jq -e --arg model "$model" '.models[] | select(.name == $model)' "$(panther_llm_config_file)" >/dev/null; then
    return 0
  fi

  local supported_models
  supported_models="$(jq -r '[.models[].name] | join(", ")' "$(panther_llm_config_file)")"
  panther_log_error "Unsupported model '$model'. Supported models: $supported_models"
}
panther_llm_config() {
  local model="$1"
  jq -r --arg model "$model" '.models[] | select(.name == $model)' "$(panther_llm_config_file)"
}
# Hub-relative paths (<repository>/<file>) of every component file the given
# model needs. Components may span several repositories.
panther_llm_model_files() {
  local model="$1"
  panther_llm_config "$model" | jq -r '.components[] | .repository + "/" + .file'
}
panther_llm_preset_file() {
  printf '%s\n' "$PANTHER_REPO_ROOT/llama-cpp/preset.ini"
}
# Preset section names are the identifiers llama-server actually serves. They mirror the model
# names in llm.config.json, which only tracks which weight files to download.
panther_loadable_llms() {
  awk -F'[][]' 'NF==3{print $2}' "$(panther_llm_preset_file)"
}
panther_assert_loadable_llm() {
  local model="$1"
  if panther_loadable_llms | grep -Fxq "$model"; then
    return 0
  fi

  local loadable_models
  loadable_models="$(panther_loadable_llms | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  panther_log_error "Unknown model '$model'. Loadable models: $loadable_models"
}
# Asks llama-manager to make a model resident. Prints nothing and returns 0 on success; on failure
# prints a human-readable reason and returns 1, so callers decide between warning and exiting.
panther_llm_request_load() {
  local model="$1"
  local response http_code body

  if ! response="$(curl -s -w '%{http_code}' -X POST 'https://localhost:8000/models/load' \
    -H 'Content-Type: application/json' \
    --insecure \
    -d "{\"model\": \"$model\"}")"; then
    printf 'cannot reach llama-manager at https://localhost:8000 - is the cluster running?\n'
    return 1
  fi

  http_code="${response: -3}"
  body="${response%???}"

  if [[ "$http_code" == '200' ]]; then
    return 0
  fi

  printf 'HTTP %s: %s\n' "$http_code" "$(jq -r '.error.message // tostring' <<<"$body" 2>/dev/null | head -1)"
  return 1
}
