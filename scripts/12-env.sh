#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_root
confirm "Sync .env GPU group IDs (VIDEO_GID/RENDER_GID)."

# =============================================================================
# 12. Environment
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE_FILE="${SCRIPT_DIR}/.env.example"

if [[ ! -f "$ENV_FILE" ]]; then
  [[ -f "$ENV_EXAMPLE_FILE" ]] || log_error "Missing $ENV_EXAMPLE_FILE"
  log_info "Creating $ENV_FILE from .env.example..."
  cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
fi

log_info "Syncing VIDEO_GID and RENDER_GID in $ENV_FILE from host groups..."
sync_env_gpu_gids "$ENV_FILE"
log_success "Environment ready (.env created if needed, GPU group IDs synced)."

