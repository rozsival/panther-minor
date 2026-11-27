#!/usr/bin/env bash

# Steps in dependency order: check refuses a host without the baseline (Ubuntu
# 26.04+, Docker), deps installs what the later steps and the CLI call, amdgpu
# and grub bring up the GPUs, memory protects llama.cpp's page cache, env
# writes .env. These are the same functions './bin/panther-minor setup <step>'
# dispatches to, so each step has one implementation.
panther_setup_all() {
  local step

  # A fresh list per run: the file lives in /tmp across runs, and the summary
  # must not repeat what an earlier run asked for.
  : >"$PANTHER_ACTIONS_FILE"

  # check exits on a missing prerequisite, before anything is installed.
  for step in check deps amdgpu grub memory env; do
    "panther_minor_setup_${step}_command"
  done

  # As the user, after the steps above, so its login-shell checks see the shell
  # they will get. A failed check is a follow-up, not a reason to abort.
  panther_log_info "Putting panther-minor on ${PANTHER_ALLOWED_USER}'s PATH..."
  if ! sudo -u "$PANTHER_ALLOWED_USER" -H "$PANTHER_CLI_BIN" install; then
    panther_register_action "Fix what 'panther-minor install' reported above, then re-run ./bin/panther-minor install as ${PANTHER_ALLOWED_USER}."
  fi

  # Prints the ACTIONS REQUIRED list the steps registered along the way: the
  # reboot for the new amdgpu driver and kernel parameters, TS_AUTHKEY, the
  # docker group. Nothing else calls it, so without this a full run ends
  # without ever showing them.
  panther_print_setup_summary
}

# Prompts for the allowed user, pre-filled from the flag, the env var or sudo.
panther_interactive_setup() {
  panther_require_root
  panther_resolve_setup_context

  echo ''
  echo '🔍 Panther Minor Setup - Interactive Mode'
  echo '========================================='

  local reply
  read -r -p "Enter allowed user (default: ${PANTHER_ALLOWED_USER}): " reply
  PANTHER_ALLOWED_USER="${reply:-$PANTHER_ALLOWED_USER}"

  # Every step resolves the user again, and a flag wins over a global there, so
  # the answer goes into the flag: otherwise a name typed over a pre-filled
  # flag would be silently replaced by the flag. Resolving once more also runs
  # the user guards on the answer.
  args['--allowed-user']="$PANTHER_ALLOWED_USER"
  panther_resolve_setup_context

  echo ''
  echo '📋 Setup Summary:'
  echo "   Allowed User: $PANTHER_ALLOWED_USER"
  echo "   Steps: check deps amdgpu grub memory env, then install"
  echo ''

  local confirm
  read -r -p 'Proceed with setup? (y/N): ' confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo 'Setup cancelled.'
    exit 0
  fi

  panther_ensure_actions_file
  PANTHER_CONFIRMED=1 panther_setup_all
}

panther_interactive_setup
