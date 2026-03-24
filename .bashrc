_panther_repo_dir="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P
)"

_panther_bin_dir="$_panther_repo_dir/bin"

eval "$("$_panther_bin_dir"/cli completions)"

unset _panther_bin_dir
unset _panther_repo_dir
