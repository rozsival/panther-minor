#!/bin/bash

# -- OpenFang entrypoint ------------------------------------------------------
# If config.toml exists, use it. Otherwise, use the default config.
if [ -f "$OPENFANG_HOME/config.toml" ]; then
  echo "Using config.toml from $OPENFANG_HOME"
else
  echo "Using default config.toml"
  cp "$OPENFANG_HOME/config.toml.default" "$OPENFANG_HOME/config.toml"
fi

# Execute original entrypoint command
openfang start
