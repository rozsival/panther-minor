panther_models_unload() {
  local model="${args[model]}"
  panther_assert_supported_model "$model"

  # Make POST request to llama-manager to unload the model (via HTTPS as external client)
  local response
  response=$(curl -s -w "%{http_code}" -X POST "https://localhost:8000/models/unload" \
    -H "Content-Type: application/json" \
    --insecure \
    -d "{\"model\": \"$model\"}")

  local http_code="${response: -3}"
  local body="${response%???}"

  if [[ "$http_code" == "200" ]]; then
    panther_log_success "Model '$model' unloaded successfully."
  elif [[ "$http_code" == "400" ]]; then
    panther_log_error "Failed to unload model '$model'. Error: $(echo "$body" | jq -r '.error.message')"
  else
    panther_log_error "Failed to unload model '$model'. HTTP status: $http_code. Response: $(echo "$body" | jq -r '.error.message')"
  fi
}

panther_models_unload
