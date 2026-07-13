# Shared helpers for the single, repository-keyed Hugging Face weight cache.
#
# All LLM and text-to-image weights live in one cache directory, with each file
# stored at its repo-relative path `<repository>/<file>`. Keying by repository
# means identical files shared across configs (e.g. the Qwen3-VL-8B encoder used
# by several t2i models) dedupe to a single copy, while same-named files from
# different repos (e.g. every LLM's mmproj-F16.gguf) never collide.

panther_hf_cache_dir() {
  printf '%s\n' "$PANTHER_MODELS_DIR/.huggingface"
}

# Hub-relative paths referenced by the text-to-image config. Pass a model name
# to exclude that model (used by `remove` to spare files another model shares).
panther_t2i_referenced_files() {
  jq -r --arg ex "${1:-}" \
    '.models[] | select(.name != $ex) | .components[] | .repository + "/" + .file' \
    "$(panther_t2i_config_file)"
}

# Hub-relative paths referenced by the LLM config.
# Pass a model name to exclude that model.
panther_llm_referenced_files() {
  jq -r --arg ex "${1:-}" \
    '.models[]
       | select(.name != $ex)
       | .repository as $r
       | .files[] | $r + "/" + .' \
    "$(panther_llm_config_file)"
}

# Every hub-relative path referenced by any model in either config.
panther_referenced_files() {
  {
    panther_t2i_referenced_files
    panther_llm_referenced_files
  } | sort -u
}

# Hub-relative paths of weight files actually present in the cache, ignoring the
# `.cache` metadata that `hf download --local-dir` writes.
panther_cache_files() {
  local cache_dir file
  cache_dir="$(panther_hf_cache_dir)"
  [[ -d "$cache_dir" ]] || return 0

  while IFS= read -r file; do
    printf '%s\n' "${file#"$cache_dir/"}"
  done < <(find "$cache_dir" -type f -not -path '*/.cache/*')
}

# Drop repository directories that hold nothing but Hugging Face metadata, then
# sweep any now-empty directories bottom-up.
panther_prune_empty_dirs() {
  local cache_dir="$1" dir
  while IFS= read -r dir; do
    if [[ -z "$(find "$dir" -type f -not -path '*/.cache/*' | head -1)" ]]; then
      rm -rf "$dir"
    fi
  done < <(find "$cache_dir" -type d -name '.cache' -exec dirname {} \;)
  find "$cache_dir" -mindepth 1 -depth -type d -empty -delete 2>/dev/null || true
}

# Delete cached files no config references anymore, then tidy empty directories.
# Called after download/remove and directly by `models prune`.
panther_prune_orphans() {
  local cache_dir
  cache_dir="$(panther_hf_cache_dir)"

  if [[ ! -d "$cache_dir" ]]; then
    panther_log_info 'No Hugging Face cache directory; nothing to prune.'
    return 0
  fi

  local -a orphans=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && orphans+=("$line")
  done < <(comm -23 <(panther_cache_files | sort -u) <(panther_referenced_files))

  if [[ ${#orphans[@]} -gt 0 ]]; then
    panther_log_warn "Found ${#orphans[@]} orphaned cached file(s) not referenced by any config:"
    printf '  - %s\n' "${orphans[@]}"
    panther_confirm "Delete these ${#orphans[@]} file(s) from the cache?"

    local file
    for file in "${orphans[@]}"; do
      rm -f "$cache_dir/$file"
    done
    panther_log_success "Pruned ${#orphans[@]} orphaned file(s) from the cache."
  else
    panther_log_success 'Hugging Face cache already clean; no orphaned files.'
  fi

  panther_prune_empty_dirs "$cache_dir"
}
