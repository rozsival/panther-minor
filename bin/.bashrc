_panther_bin_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
eval "$($_panther_bin_dir/cli completions)"
unset _panther_bin_dir
