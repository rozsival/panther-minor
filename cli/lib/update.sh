# `update` replaces the installed runtime files (release/package.sh) with another
# version's. Releases ship them as the panther-minor.tar.gz asset; a branch has no
# asset, so its source tarball is packaged by the branch's own release/package.sh.
# .manifest lists the shipped files, so files a version drops are deleted and
# everything else in the install (.env, proxy/ssl, models/.huggingface, extra/,
# docker-compose.override.yml) is never touched.

# Calls the GitHub REST API and stores the response body in PANTHER_UPDATE_API_BODY.
# Returns 1 on 404, so a caller can probe; any other failure is fatal. Runs in the
# current shell, not $(...), so a fatal error exits the command, not a subshell.
panther_update_api() {
  local path="$1"
  local body status message

  body="$(mktemp)"
  if ! status="$(curl -sSL -o "$body" -w '%{http_code}' \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$PANTHER_GITHUB_REPO/$path")"; then
    rm -f "$body"
    panther_log_error "Cannot reach the GitHub API."
  fi

  case "$status" in
  200)
    PANTHER_UPDATE_API_BODY="$(<"$body")"
    rm -f "$body"
    ;;
  404)
    rm -f "$body"
    return 1
    ;;
  *)
    message="$(jq -r '.message? // empty' "$body" 2>/dev/null || true)"
    rm -f "$body"
    panther_log_error "GitHub API /$path returned HTTP $status${message:+: $message}."
    ;;
  esac
}

# Sets PANTHER_UPDATE_TARGET_{CHANNEL,REF,COMMIT,URL} for a version argument:
# `latest`, a release tag (the `v` is optional), or a branch name.
panther_update_resolve() {
  local version="$1"
  local tag

  if [[ "$version" == latest ]]; then
    panther_update_api releases/latest || panther_log_error "$PANTHER_GITHUB_REPO has no published release."
    panther_update_resolve_release
    return
  fi

  # Characters valid in tags and branch names that need no URL encoding; anything
  # else cannot name a release or branch this command can fetch.
  [[ "$version" =~ ^[A-Za-z0-9._/-]+$ ]] || panther_log_error "No release or branch named '$version' in $PANTHER_GITHUB_REPO."

  tag="$version"
  [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] && tag="v$tag"
  if panther_update_api "releases/tags/$tag"; then
    panther_update_resolve_release
    return
  fi

  if panther_update_api "branches/$version"; then
    PANTHER_UPDATE_TARGET_CHANNEL=branch
    PANTHER_UPDATE_TARGET_REF="$(jq -r '.name' <<<"$PANTHER_UPDATE_API_BODY")"
    PANTHER_UPDATE_TARGET_COMMIT="$(jq -r '.commit.sha' <<<"$PANTHER_UPDATE_API_BODY")"
    # Checked before any prompt: such a branch has nothing to package.
    panther_update_api "contents/release/package.sh?ref=$PANTHER_UPDATE_TARGET_COMMIT" ||
      panther_log_error "Branch $PANTHER_UPDATE_TARGET_REF has no release/package.sh: it predates archive installs and cannot be installed by update."
    # The resolved commit, not the branch: a push during the update cannot change what is installed.
    PANTHER_UPDATE_TARGET_URL="https://github.com/$PANTHER_GITHUB_REPO/archive/$PANTHER_UPDATE_TARGET_COMMIT.tar.gz"
    return
  fi

  panther_log_error "No release or branch named '$version' in $PANTHER_GITHUB_REPO."
}

panther_update_resolve_release() {
  PANTHER_UPDATE_TARGET_CHANNEL=release
  PANTHER_UPDATE_TARGET_REF="$(jq -r '.tag_name' <<<"$PANTHER_UPDATE_API_BODY")"
  PANTHER_UPDATE_TARGET_COMMIT=''
  PANTHER_UPDATE_TARGET_URL="$(jq -r --arg name "$PANTHER_RELEASE_ASSET" \
    '.assets[] | select(.name == $name) | .browser_download_url' <<<"$PANTHER_UPDATE_API_BODY")"
  [[ -n "$PANTHER_UPDATE_TARGET_URL" ]] ||
    panther_log_error "Release $PANTHER_UPDATE_TARGET_REF has no $PANTHER_RELEASE_ASSET: it predates archive installs and cannot be installed by update."
}

# Sets PANTHER_UPDATE_INSTALLED_{CHANNEL,REF,COMMIT} from .release. A Git checkout
# from before archive installs reads as channel `git`, with its release tag as the
# ref when HEAD sits on one, so a downgrade from it is still detected.
panther_update_read_installed() {
  local root="$1"

  if [[ -f "$root/.release" ]]; then
    PANTHER_UPDATE_INSTALLED_CHANNEL="$(sed -n 's/^channel=//p' "$root/.release")"
    PANTHER_UPDATE_INSTALLED_REF="$(sed -n 's/^ref=//p' "$root/.release")"
    PANTHER_UPDATE_INSTALLED_COMMIT="$(sed -n 's/^commit=//p' "$root/.release")"
  elif [[ -d "$root/.git" ]]; then
    PANTHER_UPDATE_INSTALLED_CHANNEL=git
    PANTHER_UPDATE_INSTALLED_REF="$(git -C "$root" describe --tags --exact-match 2>/dev/null || git -C "$root" rev-parse --short HEAD)"
    PANTHER_UPDATE_INSTALLED_COMMIT="$(git -C "$root" rev-parse HEAD)"
  else
    panther_log_error "$root has no .release file: reinstall with $PANTHER_INSTALL_COMMAND"
  fi
}

# Human-readable version: `v14.0.0`, `feat/x@1a2b3c4`, `v13.1.0 (Git checkout)`.
panther_update_describe() {
  local channel="$1" ref="$2" commit="$3"

  case "$channel" in
  branch) printf 'branch %s@%s\n' "$ref" "${commit:0:7}" ;;
  git) printf '%s (Git checkout)\n' "$ref" ;;
  *) printf '%s\n' "$ref" ;;
  esac
}

# Succeeds when release tag $1 is older than release tag $2, by SemVer 2.0.0
# precedence: `v` prefix optional, build metadata ignored, a pre-release is older
# than its release, and pre-release identifiers compare numerically when both
# are numeric, lexically (ASCII) otherwise, numeric before alphanumeric.
panther_update_is_older() {
  local a="${1#v}" b="${2#v}"
  local a_pre='' b_pre='' i x y
  local -a a_ids b_ids

  a="${a%%+*}"
  b="${b%%+*}"
  [[ "$a" != *-* ]] || a_pre="${a#*-}"
  [[ "$b" != *-* ]] || b_pre="${b#*-}"

  IFS=. read -ra a_ids <<<"${a%%-*}"
  IFS=. read -ra b_ids <<<"${b%%-*}"
  for i in 0 1 2; do
    x="${a_ids[i]:-0}"
    y="${b_ids[i]:-0}"
    ((10#$x == 10#$y)) || return "$((10#$x < 10#$y ? 0 : 1))"
  done

  [[ -n "$a_pre" ]] || return 1
  [[ -n "$b_pre" ]] || return 0
  IFS=. read -ra a_ids <<<"$a_pre"
  IFS=. read -ra b_ids <<<"$b_pre"
  for ((i = 0; i < ${#a_ids[@]} && i < ${#b_ids[@]}; i++)); do
    x="${a_ids[i]}"
    y="${b_ids[i]}"
    [[ "$x" != "$y" ]] || continue
    if [[ "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ ]]; then
      return "$((10#$x < 10#$y ? 0 : 1))"
    fi
    [[ ! "$x" =~ ^[0-9]+$ ]] || return 0
    [[ ! "$y" =~ ^[0-9]+$ ]] || return 1
    [[ "$(printf '%s\n%s\n' "$x" "$y" | LC_ALL=C sort | sed -n 1p)" == "$x" ]]
    return
  done
  ((${#a_ids[@]} < ${#b_ids[@]}))
}

# Downloads the target into <stage> as a runtime tree with .manifest and .release.
panther_update_fetch() {
  local stage="$1" work="$2"
  local src="$work/source"

  if [[ "$PANTHER_UPDATE_TARGET_CHANNEL" == release ]]; then
    curl -fsSL "$PANTHER_UPDATE_TARGET_URL" | tar -xzf - -C "$stage" --strip-components=1 ||
      panther_log_error "Cannot download $PANTHER_UPDATE_TARGET_URL."
  else
    mkdir -p "$src"
    curl -fsSL "$PANTHER_UPDATE_TARGET_URL" | tar -xzf - -C "$src" --strip-components=1 ||
      panther_log_error "Cannot download $PANTHER_UPDATE_TARGET_URL."
    bash "$src/release/package.sh" "$src" "$stage" branch "$PANTHER_UPDATE_TARGET_REF" "$PANTHER_UPDATE_TARGET_COMMIT" ||
      panther_log_error "Packaging branch $PANTHER_UPDATE_TARGET_REF failed."
  fi

  [[ -f "$stage/.manifest" && -f "$stage/.release" && -f "$stage/bin/panther-minor" ]] ||
    panther_log_error "$PANTHER_UPDATE_TARGET_URL is not a Panther Minor runtime archive."
}

# Moves the staged files into <root> and deletes the files the installed version
# shipped and the new one does not. Every file is renamed into place, never
# rewritten: the running bin/panther-minor keeps reading its old inode. .release
# goes last: until it names the new version, a re-run takes the install for the
# old one and redoes the whole update rather than reporting it already installed.
panther_update_apply() {
  local root="$1" stage="$2" old_manifest="$3"
  local file dir

  while IFS= read -r file; do
    mkdir -p "$root/$(dirname "$file")"
    mv -f "$stage/$file" "$root/$file"
  done <"$stage/.manifest"

  while IFS= read -r file; do
    rm -f "$root/$file"
    dir="$(dirname "$file")"
    [[ "$dir" == . ]] || (cd "$root" && rmdir -p --ignore-fail-on-non-empty "$dir" 2>/dev/null) || true
  done < <(LC_ALL=C comm -23 <(LC_ALL=C sort -u "$old_manifest") <(LC_ALL=C sort -u "$stage/.manifest"))

  mv -f "$stage/.manifest" "$root/.manifest"
  mv -f "$stage/.release" "$root/.release"
}
