panther_setup_init() {
  panther_prepare_setup_step 'Extend LVM logical volume to full disk capacity.'

  panther_log_info 'Extending LVM logical volume to full disk capacity...'
  lvextend -An -l +100%FREE "$PANTHER_LVM_DEVICE"
  resize2fs "$PANTHER_LVM_DEVICE"
  panther_log_success 'Disk fully allocated.'

  panther_log_info "Setting up server timezone to ${PANTHER_TIMEZONE}..."
  timedatectl set-timezone "$PANTHER_TIMEZONE"
  panther_log_success "Timezone set to ${PANTHER_TIMEZONE}."
}

panther_setup_init
