panther_t2i_unload() {
  panther_load_dotenv "$PANTHER_ENV_FILE"
  [[ -n "${LLAMA_CPP_GPUS_STANDALONE:-}" ]] || panther_log_error "LLAMA_CPP_GPUS_STANDALONE is not set in $PANTHER_ENV_FILE. Add the GPU sets from .env.example."

  panther_log_info 'Stopping sd-server...'
  panther_compose stop stable-diffusion-cpp

  # If a previous `load --exclusive` shrank the LLMs off the image GPU, restore
  # ROCM_VISIBLE_DEVICES to all GPUs and recreate llama-cpp so it reclaims them.
  # After a plain (shared) `load` the GPU assignment was never touched, so
  # stopping sd-server is all there is to do.
  if [[ "${ROCM_VISIBLE_DEVICES:-}" != "$LLAMA_CPP_GPUS_STANDALONE" ]]; then
    panther_log_info 'Returning the dedicated image GPU(s) to the LLMs...'
    panther_upsert_env_key "$PANTHER_ENV_FILE" ROCM_VISIBLE_DEVICES "$LLAMA_CPP_GPUS_STANDALONE"
    panther_compose up --detach --force-recreate --no-deps llama-cpp
  fi

  panther_log_success 'Text-to-image model unloaded. sd-server stopped and all GPUs belong to the LLMs.'
}

panther_t2i_unload
