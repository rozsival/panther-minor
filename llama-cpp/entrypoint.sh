#!/bin/bash

# -- llama.cpp server entrypoint ----------------------------------------------
exec /opt/llama-cpp/build/bin/llama-server \
  --batch-size "$LLAMA_CPP_BATCH_SIZE" \
  --host 0.0.0.0 \
  --metrics \
  --models-max "$LLAMA_CPP_MODELS_MAX" \
  --models-preset /models/preset.ini \
  --port 8000 \
  --sleep-idle-seconds "$LLAMA_CPP_SLEEP_IDLE_SECONDS" \
  --slot-save-path /llama-slots \
  --ubatch-size "$LLAMA_CPP_UBATCH_SIZE"
