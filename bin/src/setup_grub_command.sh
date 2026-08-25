panther_setup_grub() {
  panther_prepare_setup_step 'Update GRUB kernel parameters.'

  # Single source of truth for both the config edit and the running-kernel check.
  local -a params=(amdgpu.mes=1 amdgpu.runpm=0 iommu=pt pcie_aspm=off)
  local param

  panther_log_info 'Configuring GRUB kernel parameters...'
  local raw current_cmdline updated_cmdline
  raw="$(augtool -n get /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT)"

  # Keep everything after the first ' = ' separator. Cutting on '=' instead used
  # to keep only the second field, truncating the value at its own first '=' and
  # silently dropping every later parameter (a 'resume=UUID=...' became
  # 'resume'). Augeas reports a missing node without a separator at all.
  if [[ "$raw" == *" = "* ]]; then
    current_cmdline="${raw#* = }"
  else
    current_cmdline=''
  fi

  # Strip one layer of the surrounding quotes augeas preserves verbatim, leaving
  # any inner quoting intact.
  current_cmdline="${current_cmdline#[\"\']}"
  current_cmdline="${current_cmdline%[\"\']}"

  updated_cmdline="$current_cmdline"

  for param in "${params[@]}"; do
    # Exact token match. The former '=~' test treated the parameter as a regex,
    # where '.' matches any character, so 'amdgpu.mes=1' also accepted a
    # malformed 'amdgpuxmes=1' already on the command line.
    if [[ " $current_cmdline " != *" $param "* ]]; then
      updated_cmdline="$updated_cmdline $param"
    fi
  done

  # Trim the space introduced when the value started out empty. Trimming through
  # 'xargs' would also strip quoting the value may legitimately contain.
  updated_cmdline="${updated_cmdline#"${updated_cmdline%%[![:space:]]*}"}"
  updated_cmdline="${updated_cmdline%"${updated_cmdline##*[![:space:]]}"}"

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

  # Everything above only proves /etc/default/grub is right. /proc/cmdline is what
  # the GPUs actually run with, and the two drift apart after any boot-config
  # regeneration - a release upgrade, a foreign kernel, or an edit without a
  # reboot. Reporting only on the config file turned that drift into a false
  # all-clear, which is expensive here: the tensor split-mode presets all-reduce
  # across both GPUs on every row-parallel projection, so losing 'iommu=pt' or
  # 'pcie_aspm=off' shows up as a throughput regression and nothing else.
  local running_cmdline
  local -a inactive=()
  running_cmdline="$(cat /proc/cmdline)"

  for param in "${params[@]}"; do
    if [[ " $running_cmdline " != *" $param "* ]]; then
      inactive+=("$param")
    fi
  done

  if ((${#inactive[@]} > 0)); then
    panther_log_warn "Kernel parameters missing from the running kernel: ${inactive[*]}"
    panther_register_action "Reboot to activate kernel parameters: ${inactive[*]} (GPU power management and tensor-split all-reduce performance depend on them)."
  else
    panther_log_success 'Kernel parameters active on the running kernel.'
  fi
}

panther_setup_grub
