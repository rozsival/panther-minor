#!/usr/bin/env bash

# Interactive setup that prompts for ALL configuration values with smart defaults
panther_interactive_setup() {
  # First resolve context using existing logic (flags and env vars) 
  panther_resolve_setup_context
  
  echo ""
  echo "🔍 Panther Minor Setup - Interactive Mode"
  echo "========================================="
  
  # Always prompt for each value, prefilling with current values (which may be from flags/env)
  read -r -p "Enter server name (default: ${PANTHER_SERVER_NAME:-$HOSTNAME}): " server_name
  if [[ -n "$server_name" ]]; then
    PANTHER_SERVER_NAME="$server_name"
  fi
  
  read -r -p "Enter allowed user (default: ${PANTHER_ALLOWED_USER:-$USER}): " allowed_user
  if [[ -n "$allowed_user" ]]; then
    PANTHER_ALLOWED_USER="$allowed_user"
  fi
  
  read -r -p "Enter SSH port (default: ${PANTHER_SSH_PORT:-2222}): " ssh_port
  if [[ -n "$ssh_port" ]]; then
    PANTHER_SSH_PORT="$ssh_port"
  fi
  
  read -r -p "Enter timezone (default: ${PANTHER_TIMEZONE:-Europe/Prague}): " timezone
  if [[ -n "$timezone" ]]; then
    PANTHER_TIMEZONE="$timezone"
  fi
  
  read -r -p "Enter LVM device (default: ${PANTHER_LVM_DEVICE:-/dev/ubuntu-vg/ubuntu-lv}): " lvm_device
  if [[ -n "$lvm_device" ]]; then
    PANTHER_LVM_DEVICE="$lvm_device"
  fi
  
  # Display summary and confirm
  echo ""
  echo "📋 Setup Summary:"
  echo "   Server Name: $PANTHER_SERVER_NAME"
  echo "   Allowed User: $PANTHER_ALLOWED_USER"
  echo "   SSH Port: $PANTHER_SSH_PORT"
  echo "   Timezone: $PANTHER_TIMEZONE"
  echo "   LVM Device: $PANTHER_LVM_DEVICE"
  echo ""
  
  read -r -p "Proceed with setup? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
  fi
  
  # Set the confirmed flag and run the original setup function
  PANTHER_CONFIRMED=1 panther_setup_all
}

# Run interactive setup instead of default setup
panther_interactive_setup