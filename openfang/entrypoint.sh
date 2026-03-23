#!/usr/bin/env bash

# Load OPENFANG_ prefixed env vars from .env if exists
ENV_FILE="${OPENFANG_HOME}/.env"
if [[ -f "$ENV_FILE" ]]; then
  # Source file, but only export variables that start with OPENFANG_
  set -a
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    if [[ "$key" == OPENFANG_* ]]; then
      export "$key=$value"
    fi
  done <"$ENV_FILE"
  set +a
fi

# Execute the original entrypoint
exec openfang status
