panther_t2i_load() {
  local model="${args[model]}"
  panther_assert_supported_t2i "$model"

  local diffusion uncond llm vae model_dir
  diffusion="$(panther_t2i_component_target "$model" diffusion)"
  uncond="$(panther_t2i_component_target "$model" uncond)"
  llm="$(panther_t2i_component_target "$model" llm)"
  vae="$(panther_t2i_component_target "$model" vae)"

  [[ -n "$diffusion" ]] || panther_log_error "Text-to-image model '$model' has no diffusion component in $(panther_t2i_config_file)"

  model_dir="$(panther_t2i_dir "$model")"
  if [[ ! -f "$model_dir/$diffusion" ]]; then
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

  panther_log_info "Loading text-to-image model '$model' into sd-server..."
  panther_compose up --detach --force-recreate --no-deps stable-diffusion-cpp

  panther_log_success "Text-to-image model '$model' loaded. sd-server now serves only this model."
}

panther_t2i_load
