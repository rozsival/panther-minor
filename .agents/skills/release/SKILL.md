---
name: release
description: >
  Bump version, commit, tag, and push to remote. Use when user says "release" or "bump version".
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

Update the version in **every file that carries it**. As of this writing those are:

| File                     | Occurrence                                         |
| ------------------------ | -------------------------------------------------- |
| `bin/src/bashly.yml`     | `version: X.Y.Z`                                   |
| `package.json`           | `"version": "X.Y.Z"`                               |
| `models/llm.config.json` | `"version": "X.Y.Z"`                               |
| `llama-cpp/preset.ini`   | `version = X.Y.Z`                                  |
| `models/t2i.config.json` | `"version": "X.Y.Z"`                               |
| `README.md`              | `git checkout vX.Y.Z` in the "Quick Start" section |

`bin/cli` also carries the version, at `declare -g version="X.Y.Z"`. It is **not** in that table on
purpose.

> **Never read or edit `bin/cli` during a release.** It is a 205 KB / 7,700-line generated bashly
> artifact — reading it costs ~16k tokens and has caused a release to fail mid-run. Its version line
> comes from `bin/src/bashly.yml` and is rewritten by `pnpm run build:cli` below. Bump the source, not
> the artifact.

Do **not** trust the table blindly — file locations drift. Before editing, discover

```bash
grep -rn "<CURRENT_VERSION>" --include=*.json --include=*.yml --include=*.ini --include=*.md . \
  | grep -vE "node_modules|/\.git/|pnpm-lock|CHANGELOG"
```

Update each match to the new version in-place. If your edit tool needs a fresh read to anchor a hunk,
read **only the matching line range** (e.g. `README.md:110-120`), never the whole file.

## Commit & Tag

1. **Refresh lockfile** after version bump:
   ```bash
   pnpm install
   ```
2. **Build CLI** with new version:
   ```bash
   pnpm run build:cli
   ```
3. **Verify no stale version remains** — grep for the **old** version across the repo (now that `bin/cli`
   is regenerated too). It must return nothing except intentional history (e.g. `CHANGELOG`):
   ```bash
   grep -rn "<OLD_VERSION>" --include=*.json --include=*.yml --include=*.ini --include=*.md --include=cli . \
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
6. **Create a signed tag**, then confirm it exists. Run it as its own command — hook output on stderr
   (commitlint via lefthook) can make a chained `git commit && git tag -s …` look like a failure and
   abort before the tag is created, leaving a release commit with no tag:
   ```bash
   git tag -s vX.Y.Z -m "Release vX.Y.Z"
   git tag --list vX.Y.Z
   ```
   If the second command prints nothing, the tag was **not** created. Stop and report the error — do not
   push a release commit without its tag.
7. **Push to remote** — push **sequentially**, NOT in parallel:
   ```bash
   git push origin vX.Y.Z
   git push origin main
   ```
   Push the tag first, then the branch. Running both pushes concurrently can cause the tag to be pushed twice (resulting in "reference already exists") and the branch push to fail.
   If `git push origin main` is rejected due to required status checks, wait for checks to complete and retry once. Do not retry more than once.

## Confirmation

Report back to the user:

```
✅ Release vX.Y.Z created successfully.
   - Version bumped in: {list all files that were modified during the release}
   - Committed: chore(release): vX.Y.Z
   - Tagged: vX.Y.Z
   - Pushed to remote
```

## Error Handling

- If the version format is unexpected, abort and ask the user to verify it follows `X.Y.Z` semver or is approved to be in a different format (e.g., `X.Y.Z-beta`).
- If `git push` fails (e.g., remote rejects tag, network issue), inform the user and stop. Do not retry automatically.
- Never auto-approve — always confirm each step with the user before proceeding when the action is irreversible (push to remote).
