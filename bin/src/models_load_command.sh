panther_models_load() {
  local model="${args[model]}"
  panther_assert_supported_model "$model"

  # Make POST request to llama-manager to load the model (via HTTPS as external client)
  local response
  response=$(curl -s -w "%{http_code}" -X POST "https://localhost:8000/models/load" \
    -H "Content-Type: application/json" \
    --insecure \
    -d "{\"model\": \"$model\"}")

  local http_code="${response: -3}"
  local body="${response%???}"

  if [[ "$http_code" == "200" ]]; then
    panther_log_success "Model '$model' loaded successfully."
  elif [[ "$http_code" == "400" ]]; then
    panther_log_error "Failed to load model '$model'. Error: $body"
  else
    panther_log_error "Failed to load model '$model'. HTTP status: $http_code. Response: $body"
  fi
}

panther_models_load
