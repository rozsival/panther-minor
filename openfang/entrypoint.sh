#!/bin/bash

set -euo pipefail

ENV_FILE="${OPENFANG_HOME}/.env"
OPENFANG_EXECUTABLE="${OPENFANG_EXECUTABLE:-openfang}"

# Load only OPENFANG_ prefixed env vars from the mounted project .env file.
if [[ -f "$ENV_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    line="${line#export }"
    key="${line%%=*}"

    if [[ "$key" == "$line" ]]; then
      continue
    fi

    value="${line#*=}"
    if [[ "$key" == OPENFANG_* ]]; then
      export "$key=$value"
    fi
  done <"$ENV_FILE"
fi

if [[ "$#" -eq 0 ]]; then
  set -- start
fi

first_arg_is_executable=false
if [[ "$1" == */* ]]; then
  [[ -x "$1" ]] && first_arg_is_executable=true
elif [[ "$1" != -* ]] && command -v "$1" >/dev/null 2>&1; then
  first_arg_is_executable=true
fi

if [[ "$first_arg_is_executable" == false ]]; then
  set -- "$OPENFANG_EXECUTABLE" "$@"
fi

exec "$@"
