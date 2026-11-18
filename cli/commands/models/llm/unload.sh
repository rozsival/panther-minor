panther_llm_unload() {
  local model="${args[model]}"
  panther_assert_loadable_llm "$model"

  # Make POST request to llama-manager through the proxy's loopback listener
  local response
  if ! response=$(curl -s -w "%{http_code}" -X POST "http://localhost:8000/models/unload" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$model\"}"); then
    panther_log_error "Cannot reach llama-manager at http://localhost:8000. Is the cluster running?"
  fi

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

panther_llm_unload
