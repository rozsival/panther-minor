panther_t2i_load() {
  local model="${args[model]}"
  local exclusive="${args[--exclusive]:-}"
  panther_assert_supported_t2i "$model"

  if [[ -n "$exclusive" ]]; then
    panther_load_dotenv "$PANTHER_ENV_FILE"
    [[ -n "${LLAMA_CPP_GPUS_SHARED:-}" ]] || panther_log_error "LLAMA_CPP_GPUS_SHARED is not set in $PANTHER_ENV_FILE. Add the GPU sets from .env.example."
  fi

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

  if [[ -n "$exclusive" ]]; then
    # Exclusive mode: hand image generation its dedicated SD_VISIBLE_DEVICES GPU by
    # shrinking the LLMs to LLAMA_CPP_GPUS_SHARED, so the two never contend for the
    # same VRAM during heavy image sessions. `models t2i unload` restores the LLMs
    # to all GPUs.
    panther_upsert_env_key "$PANTHER_ENV_FILE" ROCM_VISIBLE_DEVICES "$LLAMA_CPP_GPUS_SHARED"

    panther_log_info "Loading text-to-image model '$model' and dedicating GPU(s) to image generation..."
    panther_compose up --detach --force-recreate --no-deps llama-cpp stable-diffusion-cpp

    panther_log_success "Text-to-image model '$model' loaded on its dedicated GPU(s). The LLMs were moved off; run './bin/cli models t2i unload' to give the GPU(s) back."
    return 0
  fi

  panther_log_info "Loading text-to-image model '$model' into sd-server..."
  panther_compose up --detach --force-recreate --no-deps stable-diffusion-cpp

  panther_log_success "Text-to-image model '$model' loaded. sd-server now serves only this model."
}

panther_t2i_load
