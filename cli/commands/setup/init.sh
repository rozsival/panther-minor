panther_setup_init() {
  panther_prepare_setup_step 'Extend LVM logical volume to full disk capacity.'

  # The installer leaves the rest of the disk unallocated, so this claims it.
  # 'lvextend' exits non-zero when there is nothing left to claim, which under
  # 'set -e' would abort the whole run on a re-run or a fully-allocated install,
  # so the free extents are checked first. 'resize2fs' needs no such guard: it
  # exits 0 when the filesystem already spans the volume.
  local volume_group free_extents
  volume_group=$(lvs --noheadings -o vg_name "$PANTHER_LVM_DEVICE" 2>/dev/null | tr -d '[:space:]')
  free_extents=$(vgs --noheadings -o vg_free_count "$volume_group" 2>/dev/null | tr -d '[:space:]')

  if [[ "$free_extents" =~ ^[0-9]+$ ]] && ((free_extents > 0)); then
    panther_log_info 'Extending LVM logical volume to full disk capacity...'
    lvextend -An -l +100%FREE "$PANTHER_LVM_DEVICE"
  else
    panther_log_info "No unallocated extents left in ${volume_group:-the volume group}."
  fi

  resize2fs "$PANTHER_LVM_DEVICE"
  panther_log_success 'Disk fully allocated.'

  panther_log_info "Setting up server timezone to ${PANTHER_TIMEZONE}..."
  timedatectl set-timezone "$PANTHER_TIMEZONE"
  panther_log_success "Timezone set to ${PANTHER_TIMEZONE}."
}

panther_setup_init
