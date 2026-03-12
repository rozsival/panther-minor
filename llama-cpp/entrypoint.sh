#!/bin/bash
# -- llama.cpp server entrypoint ----------------------------------------------
exec /app/llama-server --host 0.0.0.0 --port 8000 --models-dir /models/.huggingface --models-preset /models/preset.ini
