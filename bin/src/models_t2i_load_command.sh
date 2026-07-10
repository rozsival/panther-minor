panther_t2i_load() {
  local model="${args[model]}"
  panther_assert_supported_t2i "$model"

  local diffusion uncond llm vae model_args cache_dir
  diffusion="$(panther_t2i_component_path "$model" diffusion)"
  uncond="$(panther_t2i_component_path "$model" uncond)"
  llm="$(panther_t2i_component_path "$model" llm)"
  vae="$(panther_t2i_component_path "$model" vae)"
  model_args="$(panther_t2i_args "$model")"

  [[ -n "$diffusion" ]] || panther_log_error "Text-to-image model '$model' has no diffusion component in $(panther_t2i_config_file)"

  cache_dir="$(panther_hf_cache_dir)"
  if [[ ! -f "$cache_dir/$diffusion" ]]; then
    panther_log_error "Text-to-image model '$model' is not downloaded. Run './bin/cli models t2i download $model' first."
  fi

  # sd-server loads exactly one model per process, so pointing the single
  # stable-diffusion-cpp container at a new model and recreating it guarantees
  # only one text-to-image model is ever resident.
  panther_upsert_env_key "$PANTHER_ENV_FILE" SD_CPP_MODEL "$model"
  panther_upsert_env_key "$PANTHER_ENV_FILE" SD_CPP_DIFFUSION_MODEL "$diffusion"
  panther_upsert_env_key "$PANTHER_ENV_FILE" SD_CPP_UNCOND_DIFFUSION_MODEL "$uncond"
  panther_upsert_env_key "$PANTHER_ENV_FILE" SD_CPP_LLM "$llm"
  panther_upsert_env_key "$PANTHER_ENV_FILE" SD_CPP_VAE "$vae"
  # Per-model sd-server flags (sampling tuning such as --flow-shift), applied on launch.
  panther_upsert_env_key "$PANTHER_ENV_FILE" SD_CPP_MODEL_ARGS "$model_args"

  panther_log_info "Loading text-to-image model '$model' into sd-server..."
  panther_compose up --detach llama-cpp --no-deps stable-diffusion-cpp

  panther_log_success "Text-to-image model '$model' loaded. sd-server now serves only this model."
}

panther_t2i_load
