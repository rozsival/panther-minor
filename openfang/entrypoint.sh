#!/bin/bash

set -e

# Load OPENFANG_ prefixed env vars from .env if exists
ENV_FILE="${OPENFANG_HOME}/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    if [[ "$key" == OPENFANG_* ]]; then
      export "$key=$value"
    fi
  done <"$ENV_FILE"
  set +a
fi

# Execute original entrypoint with args (parent CMD becomes our $@)
exec "$@"
