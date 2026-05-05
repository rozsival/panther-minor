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

Ask the user: **"What type of release is this? (major, minor, patch)"**

Wait for their answer. Then bump the version using semver:

| Type  | Current `X.Y.Z` | New `X.Y.Z` |
| ----- | --------------- | ----------- |
| major | `X.Y.Z`         | `X+1.0.0`   |
| minor | `X.Y.Z`         | `X.Y+1.0`   |
| patch | `X.Y.Z`         | `X.Y.Z+1`   |

Read `bin/src/bashly.yml` to find the current `version: X.Y.Z` field. Update it in-place.
Read `models/config.json` to find the current `version: "X.Y.Z"` field. Update it in-place.
Read `models/preset.ini` to find the current `version = X.Y.Z` line. Update it in-place.
Read `package.json` to find the current `version: "X.Y.Z"` field. Update it in-place.
Read `README.md` and update the references to the version in `git` commands (section "Quick Start").

## Commit & Tag

1. **Refresh lockfile** after version bump:
   ```bash
   pnpm install
   ```
2. **Build CLI** with new version:
   ```bash
   pnpm run build:cli
   ```
3. **Gather all changed files**:
   ```bash
   git add $(git diff --name-only HEAD)
   ```
4. **Commit**:
   ```bash
   git commit -m "chore(release): vX.Y.Z"
   ```
5. **Create a git tag**:
   ```bash
   git tag -a "vX.Y.Z" -m "Release vX.Y.Z"
   ```
6. **Push to remote**:
   ```bash
   git push origin main
   git push origin vX.Y.Z
   ```

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
