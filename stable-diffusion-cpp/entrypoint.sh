#!/bin/bash

# -- stable-diffusion.cpp (sd-server) entrypoint ------------------------------
# Serves an OpenAI-compatible image generation API (/v1/images/generations).
#
# Exactly ONE model is loaded per process (sd-server has no runtime model
# switching), which guarantees only one text-to-image model is resident at a
# time. The active model is selected by SD_CPP_MODEL and its component files;
# switch models on the host with `./bin/cli models t2i load <model>`, which
# rewrites these variables and recreates this single container.
#
# Models differ in which components they need: Ideogram 4 ships a conditional
# and an unconditional diffusion GGUF, whereas Qwen-Image ships a single
# diffusion GGUF. Each flag below is only added when its file variable is set,
# so a component that a model does not use is simply omitted.

set -euo pipefail

model="${SD_CPP_MODEL}"
# Weights live in one shared cache, each at its repo-relative path. The SD_CPP_*
# variables already carry those <repository>/<file> paths, so components only
# need the hub root prefixed.
hub_dir="$HOME/.cache/huggingface/hub"

args=(
  --listen-ip 0.0.0.0
  --listen-port 8000
)

# add_component <sd-server-flag> <filename>
# Appends the flag and its resolved path when <filename> is non-empty, failing
# fast if the model has not been downloaded yet.
add_component() {
  local flag="$1" filename="$2"

  [[ -n "$filename" ]] || return 0

  local path="$hub_dir/$filename"
  if [[ ! -f "$path" ]]; then
    echo "[stable-diffusion-cpp] missing model file: $path" >&2
    echo "[stable-diffusion-cpp] run './bin/cli models t2i download $model' on the host first" >&2
    exit 1
  fi

  args+=("$flag" "$path")
}

if [[ -z "${SD_CPP_DIFFUSION_MODEL}" ]]; then
  echo "[stable-diffusion-cpp] SD_CPP_DIFFUSION_MODEL is not set for model '$model'" >&2
  exit 1
fi

add_component --diffusion-model "${SD_CPP_DIFFUSION_MODEL}"
add_component --uncond-diffusion-model "${SD_CPP_UNCOND_DIFFUSION_MODEL}"
add_component --llm "${SD_CPP_LLM}"
add_component --vae "${SD_CPP_VAE}"

# SD_CPP_MODEL_ARGS holds this model's extra sd-server flags (sampling tuning
# such as --flow-shift) and is intentionally word-split into separate arguments.
# shellcheck disable=SC2086
exec /opt/stable-diffusion-cpp/build/bin/sd-server \
  "${args[@]}" \
  --diffusion-fa \
  --offload-to-cpu \
  ${SD_CPP_MODEL_ARGS:-}
