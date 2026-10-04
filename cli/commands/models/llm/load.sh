panther_llm_load() {
  local model="${args[model]}"
  panther_assert_loadable_llm "$model"

  local failure
  if failure="$(panther_llm_request_load "$model")"; then
    panther_log_success "Model '$model' loaded successfully."
  else
    panther_log_error "Failed to load model '$model'. $failure"
  fi
}

panther_llm_load
