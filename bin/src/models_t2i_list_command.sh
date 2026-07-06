panther_t2i_list() {
  echo '🐆 Supported text-to-image models:'
  while IFS= read -r model; do
    echo "- $model"
  done < <(panther_supported_t2i)
}

panther_t2i_list
