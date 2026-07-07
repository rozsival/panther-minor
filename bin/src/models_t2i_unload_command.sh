panther_t2i_unload() {
  # sd-server has no unload endpoint (it loads a single model for its lifetime),
  # so freeing GPU VRAM means stopping the container. The next
  # './bin/cli models t2i load <model>' or 'cluster start' brings it back.
  panther_log_info 'Stopping sd-server to free image-generation VRAM...'
  panther_compose stop stable-diffusion-cpp

  panther_log_success 'Text-to-image model unloaded. sd-server stopped and its GPU VRAM freed.'
}

panther_t2i_unload
