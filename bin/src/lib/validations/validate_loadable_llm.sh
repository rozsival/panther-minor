validate_loadable_llm() {
  local preset_file="$PANTHER_REPO_ROOT/llama-cpp/preset.ini"
  if [[ ! -f "$preset_file" ]]; then
    echo "llama.cpp preset file not found: $preset_file"
    return
  fi

  if awk -F'[][]' 'NF==3{print $2}' "$preset_file" | grep -Fxq "$1"; then
    return 0
  fi

  local loadable_models
  loadable_models="$(awk -F'[][]' 'NF==3{print $2}' "$preset_file" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  echo "must be one of: $loadable_models"
}
