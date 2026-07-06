panther_llm_list() {
  echo '🐆 Supported LLMs:'
  while IFS= read -r model; do
    echo "- $model"
  done < <(panther_supported_llms)
}

panther_llm_list
