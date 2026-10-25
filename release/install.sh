#!/usr/bin/env bash
# Installs the latest Panther Minor release:
#
#   curl -fsSL https://github.com/rozsival/panther-minor/releases/latest/download/install.sh | bash
#
# Downloads the release's runtime archive (see release/package.sh) into $PANTHER_MINOR_DIR
# (default ~/panther-minor). Installation only: host setup is `sudo ./bin/panther-minor setup`, later
# versions come from `panther-minor update`.
set -euo pipefail

# Everything runs from main, so a download cut short by the network executes nothing.
main() {
  local repo='rozsival/panther-minor'
  local dir="${PANTHER_MINOR_DIR:-$HOME/panther-minor}"
  local url="https://github.com/$repo/releases/latest/download/panther-minor.tar.gz"
  local stage ref

  info() { printf '\033[0;34m[INFO]\033[0m  %s\n' "$*"; }
  fail() {
    printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2
    exit 1
  }

  [[ $EUID -ne 0 ]] || fail "Run the installer as the user who operates the stack, not as root: it installs into $dir."
  command -v curl >/dev/null || fail 'curl is required.'
  command -v tar >/dev/null || fail 'tar is required.'

  if [[ -f "$dir/.manifest" ]]; then
    fail "Panther Minor is already installed in $dir: run '$dir/bin/panther-minor update' instead."
  fi
  if [[ -d "$dir/.git" ]]; then
    fail "$dir is a Git checkout: run '$dir/bin/panther-minor update' to convert it."
  fi
  if [[ -e "$dir" && -n "$(ls -A "$dir")" ]]; then
    fail "$dir exists and is not empty: remove it or set PANTHER_MINOR_DIR to another directory."
  fi

  mkdir -p "$dir"
  # Staged next to the target, so nothing lands in it unless the whole archive extracted.
  stage="$(mktemp -d "$dir/.install.XXXXXX")"
  # shellcheck disable=SC2064 # expand now: the local is gone when the trap fires after main
  trap "rm -rf '$stage'" EXIT

  info "Downloading the latest release from $url..."
  curl -fsSL "$url" | tar -xzf - -C "$stage" --strip-components=1
  [[ -f "$stage/.manifest" && -f "$stage/bin/panther-minor" ]] || fail "The archive from $url is not a Panther Minor release."

  shopt -s dotglob
  mv "$stage"/* "$dir"/
  shopt -u dotglob

  ref="$(sed -n 's/^ref=//p' "$dir/.release")"
  printf '\033[0;32m[OK]\033[0m    Installed Panther Minor %s into %s.\n' "$ref" "$dir"
  info "Next: cd $dir && sudo ./bin/panther-minor setup"
}

main "$@"
