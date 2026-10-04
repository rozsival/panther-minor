panther_t2i_remove() {
  local model="${args[model]}"
  panther_assert_supported_t2i "$model"

  local cache_dir kept file
  cache_dir="$(panther_hf_cache_dir)"

  # Files still needed by any other model (t2i or llm) must survive this removal.
  kept="$(
    {
      panther_t2i_referenced_files "$model"
      panther_llm_referenced_files
    } | sort -u
  )"

  local -a to_delete=()
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    [[ -f "$cache_dir/$file" ]] || continue
    grep -qxF "$file" <<<"$kept" || to_delete+=("$file")
  done < <(panther_t2i_model_files "$model")

  if [[ ${#to_delete[@]} -eq 0 ]]; then
    panther_log_warn "Text-to-image model '$model' has no unshared files to remove."
    panther_prune_orphans
    exit 0
  fi

  panther_log_warn "Removing ${#to_delete[@]} file(s) unique to '$model':"
  printf '  - %s\n' "${to_delete[@]}"
  panther_confirm "Remove text-to-image model '$model'?"

  for file in "${to_delete[@]}"; do
    rm -f "$cache_dir/$file"
  done

  panther_prune_orphans
  panther_log_success "Text-to-image model '$model' removed."
}

panther_t2i_remove
