---
name: cli-command
description: >
  Add, edit, or regenerate subcommands and flags on the Bashly-powered `./bin/panther-minor`. Use when the user
  says "add a CLI command", "add a flag to ./bin/panther-minor", "change the CLI", "regenerate the CLI", or "add a
  bashly subcommand".
---

You are the CLI maintainer for the Panther Minor Bashly CLI. `./bin/panther-minor` is powered by
[Bashly](https://bashly.dev/) and built from authored sources under `cli/`. Follow this workflow
precisely — see `docs/cli.md` for the human-facing summary of the same rules.

## The one rule that matters

> [!IMPORTANT]
> Never edit `./bin/panther-minor` directly. It is a generated artifact — **roughly 10k lines**, including the
> inlined Bashly completion engine — built from `cli/*` by `bashly generate`. Reading it burns tens of
> thousands of tokens for no benefit, and any hand
> edit is silently discarded the next time someone runs `pnpm run build:cli`. Edit the authored sources
> in `cli/` instead, then regenerate.

## Files you edit

| Path                                | Responsibility                                                                                                                           |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `cli/bashly.yml`                    | Schema source of truth: command tree, flags, args, examples, env vars, `version`                                                         |
| `cli/commands/<group>/<cmd>.sh`     | Command entrypoint (the function Bashly calls for that leaf command); path = command name, spaces → `/`                                  |
| `cli/lib/*.sh`                      | Shared helper logic (`logging.sh`, `core.sh`, `compose.sh`, `models.sh`, `llm.sh`, `t2i.sh`, `setup.sh`, `install.sh`, `completions.sh`) |
| `cli/lib/validations/validate_*.sh` | Custom argument validators referenced from `bashly.yml` via `validate: <name>`                                                           |
| `cli/initialize.sh`                 | Pre-parse normalization and bootstrapping (runs before any command)                                                                      |
| `bashly-settings.yml`               | Bashly settings (`completions: full` enables the native bash/zsh completion engine)                                                      |

Existing validators — reuse one of these instead of inventing a new one if the argument shape already
fits:

| Validator                  | Checks                                                       |
| -------------------------- | ------------------------------------------------------------ |
| `validate_not_empty`       | Value is non-blank                                           |
| `validate_integer`         | Value is an integer                                          |
| `validate_port`            | Value is an integer between 1 and 65535                      |
| `validate_file_exists`     | Value is a path to an existing file                          |
| `validate_dir_exists`      | Value is a path to an existing directory                     |
| `validate_supported_llm`   | Value matches a `name` in `models/llm.config.json`           |
| `validate_supported_t2i`   | Value matches a `name` in `models/t2i.config.json`           |
| `validate_loadable_llm`    | Value matches a `[section]` header in `llama-cpp/preset.ini` |
| `validate_cluster_service` | Value matches a known `docker compose` service name          |

A validator function prints nothing on success and an error message to stdout (via `echo`) on failure —
Bashly captures that string and reports it as the flag/arg error. Look at
`cli/lib/validations/validate_port.sh` or `validate_supported_llm.sh` for the exact shape before
writing a new one.

## Workflow

1. **Edit `cli/bashly.yml` first.** Add the command/flag/arg/env var under the right `commands:`
   nesting. Nested subcommands (e.g. `models llm bench`) are nested `commands:` blocks — match the
   existing indentation and structure exactly. Reuse `validate:`, `completions:`, and `examples:` keys
   the way sibling entries already do.
2. **Add or edit the authored command file.** A new leaf command named `<group> <subgroup> <cmd>` needs
   `cli/commands/<group>/<subgroup>/<cmd>.sh` (Bashly maps spaces to `/` and keeps hyphens, e.g.
   `proxy renew-ssl` → `cli/commands/proxy/renew-ssl.sh`) defining a `panther_<subgroup>_<cmd>()`
   function (follow the naming pattern already used by sibling files, e.g. `cli/commands/models/llm/bench.sh` defines and calls
   `panther_llm_bench`). Put shared logic used by more than one command in `cli/lib/*.sh`, not
   duplicated across command files. Quote `args` keys with a hyphen inside the name:
   `${args['--no-cache']}`, never `${args[--no-cache]}` — the shell formatter reads an unquoted subscript as
   arithmetic and rewrites it to `--no - cache`, a different key, so the flag silently stops working.
3. **Add a validator only if none of the existing ones fit**, in
   `cli/lib/validations/validate_<name>.sh`, then reference it from `bashly.yml` with
   `validate: <name>`.
4. **Regenerate:**
   ```bash
   pnpm run build:cli
   ```
   This runs `bashly generate` from the repo root, configured by `bashly-settings.yml` (`source_dir: cli`,
   `commands_dir: commands`, `target_dir: bin`, `env: production`) — do not run bare `bashly generate --force` yourself. `--force`
   recreates placeholder command files and silently overwrites the authored bodies you just wrote. The
   project's `build:cli` script intentionally omits `--force`.
5. **Validate the result:**
   ```bash
   pnpm run check   # Biome, Prettier (shell included) and ShellCheck on bin/panther-minor
   bash -n ./bin/panther-minor
   ./bin/panther-minor --help
   ./bin/panther-minor <group> --help
   ./bin/panther-minor <group> <subgroup> <cmd> --help
   ```
   Then actually invoke the new/changed command (with real or representative arguments) and confirm the
   output and exit code are correct.

## Conventions to enforce

- **Status output** goes through `panther_log_info`, `panther_log_success`, `panther_log_warn`, and
  `panther_log_error` (defined in `cli/lib/logging.sh`) — never bare `echo` for user-facing status.
  `panther_log_error` prints to stderr and exits `1`; use it for fatal validation failures inside a
  command body.
- **Env var support is declared per command** under `environment_variables:` in `bashly.yml`, not
  assumed. Resolve flag-vs-env-vs-default precedence with `panther_resolve_option '--flag' ENV_VAR
'default'` from `cli/lib/core.sh` (flag wins, then the env var, then the default) — see
  `cli/commands/models/llm/bench.sh` for a live example with `--tokens`/`PANTHER_BENCH_TOKENS`.
- **The CLI does not globally source `.env`.** Commands that need it call `panther_load_dotenv
<path>` explicitly (`cli/lib/core.sh`); Docker Compose reads `.env` itself and needs no help from
  the CLI.
- **Completions** are generated natively by Bashly 2 (`completions: full` in `bashly-settings.yml`; no
  `send_completions.sh` lib file) and exposed by `./bin/panther-minor completions [bash|zsh]`
  (`cli/commands/completions.sh`); `./bin/panther-minor install` writes the bash script where
  bash-completion lazy-loads it. Dynamic per-arg completions (e.g. listing model names) go on the
  **arg or flag**, never the command, as `completions: { dynamic: [...] }` — each entry names a
  `panther_complete_*` function in `cli/lib/completions.sh` printing one candidate per line, run in a
  subshell. `__complete` skips `cli/initialize.sh` and runs from any directory, so these functions
  read files under `$(panther_repo_root)` — never `PANTHER_*` globals or the current directory. See
  the `models llm download` `model` arg (`panther_complete_llm_models`) for the pattern. Literal
  suggestions use `static:`; file/dir completion uses `options: [files|directories]`. Smoke-test with
  `./bin/panther-minor __complete <words...> ""` from outside the repository.

## Checklist: what else to update when the command tree changes

- `docs/cli.md` — the command reference (`## 📖 Command reference`) for any added/changed command or flag, and
  the command-group table (`## 🗂️ Command groups`) if you added/removed a top-level group.
- `AGENTS.md` and the domain docs in `docs/` (e.g. `docs/models.md`, `docs/operations.md`) — if the
  new/changed command is user-facing and those docs mention the CLI surface.
- Shell completions — nothing to do: every `<TAB>` asks `bin/panther-minor __complete`, so
  `pnpm run build:cli` is enough.
- Any wizard/skill that shells out to `./bin/panther-minor` (e.g. `.agents/skills/add-model/SKILL.md`) — check
  whether it references the exact subcommand or flag name you changed.

## Error handling

- **`./bin/panther-minor` behaves differently than `cli/` suggests it should.** The generated artifact is out
  of sync with its sources. Run `pnpm run build:cli` and re-test; never hand-patch `./bin/panther-minor` to paper
  over the mismatch.
- **`bash -n ./bin/panther-minor` reports a syntax error.** The line number is inside the generated file, but the
  bug is almost always in the authored `cli/commands/**/*.sh` or `cli/lib/*.sh` file that was
  spliced in at that point — find the corresponding authored file and fix it there, then regenerate.
- **A validator "fails silently" (bad input is accepted, or a good input is rejected with no clear
  reason).** Validator functions communicate failure purely by printing a non-empty string to stdout;
  a validator that does `return 1` without echoing anything looks like success to Bashly. Check that
  every failure path in the `validate_*.sh` file emits an `echo` message before returning.
