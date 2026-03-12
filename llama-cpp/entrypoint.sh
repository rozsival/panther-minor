#!/bin/bash
# llama.cpp server entrypoint script to load parameters from model.json and launch the server
MODEL=${1:-"panther-minor"}
CONFIG_FILE="/models/$MODEL/model.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Model file \"$CONFIG_FILE\" not found."
    exit 1
fi

# Find base parameters
HF=$(jq -r '.model' "$CONFIG_FILE")
SYSTEM_PROMPT="/models/$MODEL/system.txt"

# Init ARGS with Hugging Face model and system prompt
ARGS="--hf $HF --system-prompt-file $SYSTEM_PROMPT"

# Dynamically add parameters from config.json
while IFS=$'\t' read -r key value; do
    if [ "$value" == "true" ]; then
        # Boolean flags (true) - add as --key
        ARGS+=" --$key"
    elif [ "$value" != "false" ] && [ "$value" != "null" ]; then
        # Standard key-value pairs - add as --key value
        ARGS+=" --$key $value"
    fi
done < <(jq -r '.params | to_entries | .[] | "\(.key)\t\(.value)"' "$CONFIG_FILE")

echo "Launching llama-server with dynamic args: $ARGS"
exec /llama-server --host 0.0.0.0 --port 8000 --flash-attn on --numa distribute --split-mode layer -- "$ARGS"
