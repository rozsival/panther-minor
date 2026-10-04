---
name: release
description: >
  Bump version on a release branch, open a PR to main, and tag the merged commit. Use when user says
  "release" or "bump version".
---

You are the release engineer for Panther Minor. Follow this workflow precisely.

## Prerequisites

1. **Check branch** — run `git rev-parse --abbrev-ref HEAD`. Must be `main`.
   - If not on `main`, abort and tell the user to switch to `main` first.
2. **Check for uncommitted changes** — run `git status --porcelain`. Must be empty.
   - If dirty, abort and ask the user to commit or stash changes first.
3. **Pull latest** — run `git pull --rebase` to ensure you're up to date.

## Version Bump

Ask the user what type of release this is (major, minor, patch). Prefer tool to ask question if available, otherwise ask in the chat.

Wait for their answer. Then bump the version using semver:

| Type  | Current `X.Y.Z` | New `X.Y.Z` |
| ----- | --------------- | ----------- |
| major | `X.Y.Z`         | `X+1.0.0`   |
| minor | `X.Y.Z`         | `X.Y+1.0`   |
| patch | `X.Y.Z`         | `X.Y.Z+1`   |

## Release Branch

Agents never push to `main`: it only accepts rebase-merged PRs with a code-owner review. The release
commit goes through a `release/vX.Y.Z` branch instead.

1. **Check the version is free** — neither the tag nor the branch may exist on the remote:
   ```bash
   git ls-remote origin refs/tags/vX.Y.Z refs/heads/release/vX.Y.Z
   ```
   It must print nothing. Otherwise abort and report what exists.
2. **Create the branch** from the freshly pulled `main`:
   ```bash
   git switch -c release/vX.Y.Z
   ```

## Update the Version

Update the version in **every file that carries it**. As of this writing those are:

| File                     | Occurrence                                         |
| ------------------------ | -------------------------------------------------- |
| `cli/bashly.yml`         | `version: X.Y.Z`                                   |
| `package.json`           | `"version": "X.Y.Z"`                               |
| `models/llm.config.json` | `"version": "X.Y.Z"`                               |
| `llama-cpp/preset.ini`   | `version = X.Y.Z`                                  |
| `models/t2i.config.json` | `"version": "X.Y.Z"`                               |
| `README.md`              | `git checkout vX.Y.Z` in the "Quick Start" section |

`bin/panther-minor` also carries the version, at `declare -g version="X.Y.Z"`. It is **not** in that table on
purpose.

> **Never read or edit `bin/panther-minor` during a release.** It is a large generated bashly artifact (see
> `.agents/skills/cli-command/SKILL.md`) — reading it costs tens of thousands of tokens and has caused a release to fail mid-run. Its version line
> comes from `cli/bashly.yml` and is rewritten by `pnpm run build:cli` below. Bump the source, not
> the artifact.

Do **not** trust the table blindly — file locations drift. Before editing, discover

```bash
grep -rn "<CURRENT_VERSION>" --include=*.json --include=*.yml --include=*.ini --include=*.md . \
  | grep -vE "node_modules|/\.git/|pnpm-lock|CHANGELOG"
```

Update each match to the new version in-place. If your edit tool needs a fresh read to anchor a hunk,
read **only the matching line range** (e.g. `README.md:110-120`), never the whole file.

## Commit & Pull Request

1. **Refresh lockfile** after version bump:
   ```bash
   pnpm install
   ```
2. **Build CLI** with new version:
   ```bash
   pnpm run build:cli
   ```
3. **Verify no stale version remains** — grep for the **old** version across the repo (now that `bin/panther-minor`
   is regenerated too). It must return nothing except intentional history (e.g. `CHANGELOG`):
   ```bash
   grep -rn "<OLD_VERSION>" --include=*.json --include=*.yml --include=*.ini --include=*.md --include=panther-minor . \
     | grep -vE "node_modules|/\.git/|pnpm-lock|CHANGELOG"
   ```
   If anything unexpected prints, update it before continuing.
4. **Gather all changed files**:
   ```bash
   git add $(git diff --name-only HEAD)
   ```
5. **Commit**:
   ```bash
   git commit -m "chore(release): vX.Y.Z"
   ```
6. **Push the branch** — confirm with the user first:
   ```bash
   git push -u origin release/vX.Y.Z
   ```
7. **Open the PR**:
   ```bash
   gh pr create --base main --head release/vX.Y.Z --title "chore(release): vX.Y.Z" \
     --body "Release vX.Y.Z. Rebase-merge, then the tag is pushed from the merged commit."
   ```
8. **Wait for the required checks** (`qa`, `test`):
   ```bash
   gh pr checks release/vX.Y.Z --watch --required
   ```
   If a check fails, stop and report it. Do not push fixes onto the release branch unasked.
9. **Hand the merge to the user** — print the PR URL and ask them to review and merge it with **Rebase and
   merge** (the only method `main` allows). Never merge it yourself, never use `--admin` or any ruleset
   bypass. Wait for the user to confirm, then verify:
   ```bash
   gh pr view release/vX.Y.Z --json state --jq .state
   ```
   It must print `MERGED`. Anything else: stop, nothing gets tagged.

## Tag

The tag goes on `main`'s copy of the release commit, never the branch's: a rebase merge rewrites every
commit, so the SHA on `release/vX.Y.Z` never reaches `main`.

1. **Update `main`**:
   ```bash
   git switch main
   git pull --rebase
   ```
2. **Find the merged release commit**:
   ```bash
   git log main --format=%H -n 1 --grep='^chore(release): vX.Y.Z$'
   ```
   It must print exactly one SHA. If it prints nothing, stop and report — do not tag `HEAD` instead.
3. **Create an annotated tag** on that SHA, then confirm it exists. Annotated, not signed: agent sessions
   hold no signing key (`tag.gpgsign = false`), so `git tag -s` fails there:
   ```bash
   git tag -a vX.Y.Z <SHA> -m "Release vX.Y.Z"
   git tag --list vX.Y.Z
   ```
   If the second command prints nothing, the tag was **not** created. Stop and report the error.
4. **Push the tag** — confirm with the user first. This triggers `.github/workflows/release.yml`:
   ```bash
   git push origin vX.Y.Z
   ```
5. **Clean up** the local branch (`-D`: the rebase merge leaves its original commits unmerged by SHA):
   ```bash
   git branch -D release/vX.Y.Z
   git fetch --prune
   ```

## Confirmation

Report back to the user:

```
✅ Release vX.Y.Z created successfully.
   - Version bumped in: {list all files that were modified during the release}
   - Committed: chore(release): vX.Y.Z on release/vX.Y.Z
   - PR: {PR URL}, rebase-merged into main
   - Tagged: vX.Y.Z on {merged SHA}, pushed to remote
```

## Error Handling

- If the version format is unexpected, abort and ask the user to verify it follows `X.Y.Z` semver or is approved to be in a different format (e.g., `X.Y.Z-beta`).
- If `git push` fails (e.g., remote rejects the branch or tag, network issue), inform the user and stop. Do not retry automatically.
- Never push to `main`, never merge the release PR, never bypass branch rules — `main` changes only through the user's merge.
- Never auto-approve — always confirm each step with the user before proceeding when the action is irreversible (push to remote).
