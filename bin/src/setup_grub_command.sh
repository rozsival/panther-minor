panther_setup_grub() {
  panther_prepare_setup_step 'Update GRUB kernel parameters.'

  panther_log_info 'Configuring GRUB kernel parameters...'
  local current_cmdline updated_cmdline
  current_cmdline="$(augtool -n get /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT | cut -d'=' -f2 | tr -d '"' | tr -d "'")"
  updated_cmdline="$current_cmdline"

  for param in amdgpu.mes=1 amdgpu.runpm=0 iommu=pt pcie_aspm=off; do
    if [[ ! "$current_cmdline" =~ $param ]]; then
      updated_cmdline="$updated_cmdline $param"
    fi
  done

  updated_cmdline="$(echo "$updated_cmdline" | xargs)"

  if [[ "$current_cmdline" != "$updated_cmdline" ]]; then
    panther_log_info "Updating GRUB_CMDLINE_LINUX_DEFAULT to: $updated_cmdline"
    augtool -s <<AUGEOF
set /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT "'$updated_cmdline'"
AUGEOF
    panther_log_info 'Running update-grub...'
    update-grub
    panther_log_success 'GRUB configuration updated.'
  else
    panther_log_success 'GRUB kernel parameters already set.'
  fi
}

panther_setup_grub
