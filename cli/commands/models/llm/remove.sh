panther_llm_remove() {
  local model="${args[model]}"
  panther_assert_supported_llm "$model"

  local model_config model_name cache_dir kept file
  model_config="$(panther_llm_config "$model")"
  [[ -n "$model_config" ]] || panther_log_error "Model '$model' not found in $(panther_llm_config_file)"
  model_name="$(jq -r '.name' <<<"$model_config")"
  cache_dir="$(panther_hf_cache_dir)"

  # Files still needed by any other model (llm or t2i) must survive this removal.
  kept="$(
    {
      panther_llm_referenced_files "$model"
      panther_t2i_referenced_files
    } | sort -u
  )"

  local -a to_delete=()
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    [[ -f "$cache_dir/$file" ]] || continue
    grep -qxF "$file" <<<"$kept" || to_delete+=("$file")
  done < <(panther_llm_model_files "$model")

  if [[ ${#to_delete[@]} -eq 0 ]]; then
    panther_log_warn "Model '$model' has no unshared files to remove."
    panther_prune_orphans
    exit 0
  fi

  panther_log_warn "Removing ${#to_delete[@]} file(s) unique to '$model':"
  printf '  - %s\n' "${to_delete[@]}"
  panther_confirm "Remove model '$model'?"

  for file in "${to_delete[@]}"; do
    rm -f "$cache_dir/$file"
  done

  panther_prune_orphans
  panther_log_success "Model '$model' removed."
}

panther_llm_remove
