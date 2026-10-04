# 🧪 Development

> How to work on Panther Minor itself: toolchain, quality checks, tests, commit rules, CI, releases, and the agent
> assets that automate recurring maintenance.

**Related:** [CLI reference](cli.md#-maintainer-workflow) · [Architecture](architecture.md#-repository-layout) ·
[Documentation index](README.md)

---

## 🧰 Toolchain

| Tool              | Version / config                         | Role                                        |
| ----------------- | ---------------------------------------- | ------------------------------------------- |
| Node.js           | `24.x` (`engines`)                       | Managers, exporters, tests                  |
| pnpm              | `packageManager` in `package.json`       | Package manager and script runner           |
| Biome (Ultracite) | `biome.jsonc`                            | JS/JSON lint and format                     |
| Prettier          | `prettier.config.js` (`printWidth: 120`) | Markdown, YAML, TOML, `package.json` format |
| Bashly            | `bashly-settings.yml`                    | Generates `bin/panther-minor` from `cli/`   |
| Lefthook          | `lefthook.yml`                           | Git hooks                                   |
| commitlint        | `commitlint.config.js`                   | Conventional Commits enforcement            |
| Renovate          | `renovate.json`                          | Dependency updates                          |

```bash
pnpm install   # also installs the Git hooks outside CI
```

## ✅ Quality checks

| Task                         | Command              |
| ---------------------------- | -------------------- |
| Check code + misc formatting | `pnpm run check`     |
| Auto-fix code + formatting   | `pnpm run fix`       |
| Lint only                    | `pnpm run lint`      |
| Run tests (`node --test`)    | `pnpm run test`      |
| Regenerate the CLI           | `pnpm run build:cli` |

Tests live next to their subject as `*.test.js` (`llama-cpp/`, `stable-diffusion-cpp/`).

### Git hooks

| Hook         | Runs                                                                                                            |
| ------------ | --------------------------------------------------------------------------------------------------------------- |
| `commit-msg` | `commitlint`                                                                                                    |
| `pre-commit` | `build:cli` on CLI source changes, `ultracite fix` on JS/MD/JSON, Prettier on MD/YAML/TOML; fixes are re-staged |

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

| Workflow                        | Trigger                         | Jobs                                                                         |
| ------------------------------- | ------------------------------- | ---------------------------------------------------------------------------- |
| `.github/workflows/ci.yml`      | Push / PR to `main`             | `qa`: commitlint, `biome ci`, `prettier --check`; `test`: `pnpm run test`    |
| `.github/workflows/release.yml` | Tag `v*.*.*` or manual dispatch | Validates the SemVer tag, publishes a GitHub release with a commit changelog |

Releases are cut from `main` by bumping every version-carrying file (`cli/bashly.yml`, `package.json`,
`models/*.config.json`, `llama-cpp/preset.ini`, the root README quick start), committing, tagging `vX.Y.Z` and pushing.
The `release` agent skill performs the whole sequence.

## 🤖 Agent assets

| Asset                              | Purpose                                                    |
| ---------------------------------- | ---------------------------------------------------------- |
| `AGENTS.md`                        | Project context and rules for AI assistants                |
| `.github/copilot-instructions.md`  | Copilot PR review guidance                                 |
| `.agents/plans/`                   | Feature plans, `YYYY-MM-DD-<short-description>.md`         |
| `.agents/skills/add-model/`        | Wizard to add an LLM across catalog, presets and harnesses |
| `.agents/skills/cli-command/`      | Add or change Bashly CLI commands and flags                |
| `.agents/skills/harness-config/`   | Install or update OMP / Pi / OpenCode presets locally      |
| `.agents/skills/ideogram4-prompt/` | Generate valid Ideogram 4 JSON prompts                     |
| `.agents/skills/release/`          | Version bump, commit, tag and push                         |
| `.agents/skills/rocm-upgrade/`     | Upgrade ROCm, `amdgpu`, base OS or kernel across the stack |
| `.agents/skills/tune-preset/`      | Measurement-first `llama.cpp` preset tuning                |

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

CI runs `biome ci` and `prettier --check` on the whole repository. Run `pnpm run check` before pushing, or let the
pre-commit hook fix staged files.
