panther_llm_config_file() {
  printf '%s\n' "$PANTHER_MODELS_DIR/llm/config.json"
}
panther_supported_llms() {
  jq -r '.models[] | .name + (if .thinking == true then " (thinking)" else "" end)' "$(panther_llm_config_file)"
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
# Hub-relative paths (<repository>/<file>) of every file the given model needs.
panther_llm_model_files() {
  local model="$1"
  panther_llm_config "$model" | jq -r \
    '.repository as $r
       | ($r + "/" + .file),
         (if .mmproj then $r + "/" + .mmproj else empty end),
         (if .draft then $r + "/" + .draft else empty end)'
}
