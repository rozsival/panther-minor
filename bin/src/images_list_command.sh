panther_images_list() {
  echo '🐆 Supported image models:'
  while IFS= read -r model; do
    echo "- $model"
  done < <(panther_supported_images)
}

panther_images_list
