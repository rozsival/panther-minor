panther_repo_root() {
  # From the real file: `install` reaches bin/panther-minor through a symlink in
  # ~/.local/bin, and the completion functions below run from any directory.
  (cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
}

# Candidates for the dynamic `completions:` in bashly.yml. `panther-minor
# __complete` skips initialize.sh, so these resolve the repository themselves
# instead of reading its globals; each runs on every <TAB>, so they only read files.
panther_complete_llm_models() {
  jq -r '.models.[] | .name' "$(panther_repo_root)/models/llm.config.json"
}
panther_complete_llm_presets() {
  awk -F'[][]' 'NF==3{print $2}' "$(panther_repo_root)/llama-cpp/preset.ini"
}
panther_complete_t2i_models() {
  jq -r '.models.[] | .name' "$(panther_repo_root)/models/t2i.config.json"
}
panther_complete_services() {
  yq '.services | keys[]' "$(panther_repo_root)/docker-compose.yml"
}
