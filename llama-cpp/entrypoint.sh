#!/bin/bash

# -- llama.cpp server entrypoint ----------------------------------------------
exec /opt/llama-cpp/build/bin/llama-server \
  --batch-size "$LLAMA_CPP_BATCH_SIZE" \
  --cache-idle-slots \
  --cache-prompt \
  --cache-ram "$LLAMA_CPP_CACHE_RAM" \
  --cache-reuse 256 \
  --host 0.0.0.0 \
  --kv-unified \
  --metrics \
  --models-max "$LLAMA_CPP_MODELS_MAX" \
  --models-preset "$HOME/.cache/huggingface/preset.ini" \
  --parallel 2 \
  --port 8000 \
  --slots \
  --spec-default \
  --sleep-idle-seconds "$LLAMA_CPP_SLEEP_IDLE_SECONDS" \
  --slot-save-path "$HOME/.cache/slots" \
  --ubatch-size "$LLAMA_CPP_UBATCH_SIZE"
