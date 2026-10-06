# 🧪 Development

> How to work on Panther Minor itself: toolchain, quality checks, tests, commit rules, CI, releases, and the agent
> assets that automate recurring maintenance.

**Related:** [CLI reference](cli.md#-maintainer-workflow) · [Architecture](architecture.md#-repository-layout) ·
[Documentation index](README.md)

---

## 🧰 Toolchain

| Tool              | Version / config                                                | Role                                                                                                     |
| ----------------- | --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Node.js           | `24.x` (`engines`)                                              | Managers, exporters, tests                                                                               |
| pnpm              | `packageManager` in `package.json`                              | Package manager and script runner                                                                        |
| Biome (Ultracite) | `biome.jsonc`                                                   | JS/JSON lint and format                                                                                  |
| Prettier          | `prettier.config.js` (`printWidth: 120`)                        | Markdown, YAML, TOML, `package.json` and shell (`*.sh`, via `prettier-plugin-sh` as `shfmt -i 2`) format |
| ShellCheck        | `shellcheck` package (pins the binary, downloaded on first run) | Lints `bin/panther-minor` (which holds every `cli/` source) and the container entrypoints                |
| Bashly            | `bashly-settings.yml`                                           | Generates `bin/panther-minor` from `cli/`                                                                |
| Lefthook          | `lefthook.yml`                                                  | Git hooks                                                                                                |
| commitlint        | `commitlint.config.js`                                          | Conventional Commits enforcement                                                                         |
| Renovate          | `renovate.json`                                                 | Dependency updates                                                                                       |

```bash
pnpm install   # also installs the Git hooks outside CI
```

## ✅ Quality checks

| Task                          | Command              |
| ----------------------------- | -------------------- |
| Check code, formatting, shell | `pnpm run check`     |
| Auto-fix code + formatting    | `pnpm run fix`       |
| Lint only                     | `pnpm run lint`      |
| Run tests (`node --test`)     | `pnpm run test`      |
| Regenerate the CLI            | `pnpm run build:cli` |

Tests live next to their subject as `*.test.js` (`llama-cpp/`, `stable-diffusion-cpp/`).

### Git hooks

| Hook         | Runs                                                                                                                                       |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `commit-msg` | `commitlint`                                                                                                                               |
| `pre-commit` | Prettier, then `build:cli`, then ShellCheck on shell changes; `ultracite fix` on JS/MD/JSON, Prettier on MD/YAML/TOML; fixes are re-staged |

## 📝 Rules

1. **Code style** — Biome with the Ultracite preset; never hand-format, run `pnpm run fix`.
2. **Inference backends** — custom ROCm builds of `llama.cpp` and `stable-diffusion.cpp` for `gfx1201` only.
3. **Packages** — `apt-get` only in scripts and Dockerfiles, never `apt`; use `apt-get upgrade --with-new-pkgs` where
   `apt upgrade` was meant.
4. **Commits** — [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/), lowercase, no final
   punctuation, ≤ 100 characters (e.g. `docs: restructure documentation into docs dir`).
5. **CLI** — follow the [maintainer workflow](cli.md#-maintainer-workflow).
6. **Docs** — follow the [documentation conventions](README.md#-documentation-conventions); update the page that
   states a number when you change it.

## 🔁 CI and releases

| Workflow                        | Trigger                        | Jobs                                                                                              |
| ------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------- |
| `.github/workflows/ci.yml`      | Push / PR to `main`            | `qa`: commitlint, `biome ci`, `prettier --check`, ShellCheck; `test`: `pnpm run test`             |
| `.github/workflows/release.yml` | Push to `main` or tag `v*.*.*` | On a `chore(release): vX.Y.Z` commit: tags it, publishes a GitHub release with a commit changelog |

Releases go through a `release/vX.Y.Z` branch: bump every version-carrying file (`cli/bashly.yml`, `package.json`,
`models/*.config.json`, `llama-cpp/preset.ini`, the root README quick start), commit as `chore(release): vX.Y.Z` and
open a PR. Rebase-merging it is the release: `release.yml` creates the tag on the merged commit, since a tag pushed
with `GITHUB_TOKEN` would not trigger a workflow. A missed release is recovered by pushing the `vX.Y.Z` tag onto its
release commit yourself, which runs the same workflow. The `release` agent skill prepares the PR, stops for your
merge, then watches the release run and verifies the tag.

## 🤖 Agent assets

| Asset                               | Purpose                                                    |
| ----------------------------------- | ---------------------------------------------------------- |
| `AGENTS.md`                         | Project context and rules for AI assistants                |
| `.github/copilot-instructions.md`   | Copilot PR review guidance                                 |
| `.agents/plans/`                    | Feature plans, `YYYY-MM-DD-<short-description>.md`         |
| `.agents/skills/add-model/`         | Wizard to add an LLM across catalog, presets and harnesses |
| `.agents/skills/cli-command/`       | Add or change Bashly CLI commands and flags                |
| `.agents/skills/harness-config/`    | Install or update OMP / Pi / OpenCode presets locally      |
| `.agents/skills/ideogram4-prompt/`  | Generate valid Ideogram 4 JSON prompts                     |
| `.agents/skills/panther-minor-cli/` | Operate the workstation through `panther-minor` safely     |
| `.agents/skills/release/`           | Version bump on a release branch and PR to `main`          |
| `.agents/skills/rocm-upgrade/`      | Upgrade ROCm, `amdgpu`, base OS or kernel across the stack |
| `.agents/skills/tune-preset/`       | Measurement-first `llama.cpp` preset tuning                |

---

## ❓ FAQ

### My commit was rejected by the `commit-msg` hook. Why?

The message is not a valid lowercase Conventional Commit of ≤ 100 characters without final punctuation.

### The pre-commit hook changed my files. Is that expected?

Yes. It regenerates the CLI and runs the formatters, then re-stages the fixed files.

### Where should a new document go?

In `docs/`, as one kebab-case file per domain, linked from the [documentation index](README.md). Agent-only context
stays in `AGENTS.md` or a skill.

### Why does CI fail on formatting when it passed locally?

CI runs `biome ci`, `prettier --check` and ShellCheck on the whole repository. Run `pnpm run check` before pushing, or
let the pre-commit hook fix staged files.
