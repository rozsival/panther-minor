panther_llm_download() {
  local model="${args[model]}"
  local force="${args[--force]:-}"
  panther_assert_supported_llm "$model"
  panther_load_dotenv "$PANTHER_ENV_FILE"

  local model_config model_name cache_dir
  model_config="$(panther_llm_config "$model")"
  [[ -n "$model_config" ]] || panther_log_error "Model '$model' not found in $(panther_llm_config_file)"

  model_name="$(jq -r '.name' <<<"$model_config")"
  cache_dir="$(panther_hf_cache_dir)"

  # A model's components may span several repositories, so batch the includes of
  # each repository into a single `hf download` call.
  local repository file all_present
  local -a files hf_download_args
  while IFS= read -r repository; do
    mapfile -t files < <(jq -r --arg repo "$repository" \
      '.components[] | select(.repository == $repo) | .file' <<<"$model_config")

    all_present=1
    for file in "${files[@]}"; do
      [[ -f "$cache_dir/$repository/$file" ]] || all_present=0
    done

    if [[ "$all_present" == "1" && -z "$force" ]]; then
      panther_log_info "Files of '$model_name' from '$repository' already present; skipping (use --force to re-download)."
      continue
    fi

    hf_download_args=("$repository" --local-dir "$cache_dir/$repository")
    for file in "${files[@]}"; do
      [[ -n "$force" ]] && rm -f "$cache_dir/$repository/$file"
      hf_download_args+=(--include "$file")
    done

    panther_log_info "Downloading '$model_name' from '$repository'..."
    hf download "${hf_download_args[@]}"
  done < <(jq -r '[.components[].repository] | unique | .[]' <<<"$model_config")

  # Reclaim files this or another model no longer references (e.g. after a config edit).
  panther_prune_orphans
  panther_log_success "Model '$model_name' ready for use."
}

panther_llm_download
