#!/bin/bash

# -- llama.cpp server entrypoint ----------------------------------------------
exec /opt/llama-cpp/build/bin/llama-server \
  --batch-size 1024 \
  --host 0.0.0.0 \
  --metrics \
  --models-max 1 \
  --models-preset /models/preset.ini \
  --port 8000 \
  --ubatch-size 256
