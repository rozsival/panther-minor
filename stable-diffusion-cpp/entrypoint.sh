#!/bin/bash

# -- stable-diffusion.cpp (sd-server) entrypoint ------------------------------
# Serves an OpenAI-compatible image generation API (/v1/images/generations).
# Ideogram 4 is a multi-part model: two diffusion GGUFs (conditional and
# unconditional), a Qwen3-VL LLM text encoder, and the Flux2 autoencoder (VAE).

set -euo pipefail

model_dir="$HOME/.cache/huggingface/hub/${SD_CPP_MODEL:-ideogram-4}"

diffusion_model="$model_dir/${SD_CPP_DIFFUSION_MODEL:-ideogram4-Q4_0.gguf}"
uncond_diffusion_model="$model_dir/${SD_CPP_UNCOND_DIFFUSION_MODEL:-ideogram4_uncond-Q4_0.gguf}"
llm="$model_dir/${SD_CPP_LLM:-Qwen3VL-8B-Instruct-Q4_K_M.gguf}"
vae="$model_dir/${SD_CPP_VAE:-flux2-vae.safetensors}"

for file in "$diffusion_model" "$uncond_diffusion_model" "$llm" "$vae"; do
  if [[ ! -f "$file" ]]; then
    echo "[stable-diffusion-cpp] missing model file: $file" >&2
    echo "[stable-diffusion-cpp] run './bin/cli images download ${SD_CPP_MODEL:-ideogram-4}' on the host first" >&2
    exit 1
  fi
done

# shellcheck disable=SC2086
exec /opt/stable-diffusion-cpp/build/bin/sd-server \
  --listen-ip 0.0.0.0 \
  --listen-port 8000 \
  --diffusion-model "$diffusion_model" \
  --uncond-diffusion-model "$uncond_diffusion_model" \
  --llm "$llm" \
  --vae "$vae" \
  --diffusion-fa \
  --offload-to-cpu \
  ${SD_CPP_EXTRA_ARGS:-}
