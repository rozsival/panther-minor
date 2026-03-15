#!/bin/bash
# -- llama.cpp server entrypoint ----------------------------------------------
exec /opt/llama-cpp/build/bin/llama-server --host 0.0.0.0 --port 8000 --metrics --models-max 1 --models-preset /models/preset.ini
