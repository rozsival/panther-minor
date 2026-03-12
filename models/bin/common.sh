# -- Commons for models bin ---------------------------------------------------
DIR=$(dirname "$(realpath "$0")")
MODELS_DIR="$DIR/.."
HF_DIR="$MODELS_DIR/.huggingface"
CONFIG_FILE="$MODELS_DIR/config.json"

# List of supported models
SUPPORTED_MODELS=()
while IFS= read -r model; do
  SUPPORTED_MODELS+=("$model")
done < <(jq -r '.models[] | .name' "$CONFIG_FILE")

# Function to check if a model is supported
function assert_supported_model() {
  local model="$1"

  for supported in "${SUPPORTED_MODELS[@]}"; do
    if [[ "$supported" == "$model" ]]; then
      return 0
    fi
  done

  echo "Error: Unsupported model '$model'. Supported models: ${SUPPORTED_MODELS[*]}"
  return 1
}
