panther_setup_memory() {
  panther_prepare_root_step 'Protect the llama.cpp memory with the llm.slice systemd unit.'

  # llama-cpp runs in this slice (cgroup_parent in docker-compose.yml). 96G covers Qwen3.8-Flash-Next's host-resident
  # weights (~65 GiB: 40 expert blocks + the n-gram table) plus LLAMA_CPP_CACHE_RAM, with headroom; see docs/llm.md#host-memory-protection.
  tee /etc/systemd/system/llm.slice <<UNIT
[Unit]
Description=panther-minor llama.cpp (memory-protected)

[Slice]
MemoryLow=96G
UNIT
  systemctl daemon-reload
  panther_log_success 'llm.slice memory protection configured.'
}

panther_setup_memory
