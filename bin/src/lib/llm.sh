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
# Preset section names are the identifiers llama-server actually serves, so they
# carry the reasoning variants (e.g. 'DeepSeek-V4-Flash-0731-thinking') that llm.config.json
# does not - that file only tracks which weight files to download.
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
