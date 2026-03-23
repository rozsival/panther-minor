panther_models_list() {
  echo '🐆 Supported models:'
  while IFS= read -r model; do
    echo "- $model"
  done < <(panther_supported_models)
}

panther_models_list
