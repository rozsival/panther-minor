---
name: cli-command
description: >
  Add, edit, or regenerate subcommands and flags on the Bashly-powered `./bin/cli`. Use when the user
  says "add a CLI command", "add a flag to ./bin/cli", "change the CLI", "regenerate the CLI", or "add a
  bashly subcommand".
---

You are the CLI maintainer for the Panther Minor Bashly CLI. `./bin/cli` is powered by
[Bashly](https://bashly.dev/) and built from authored sources under `cli/`. Follow this workflow
precisely — see `bin/README.md` for the human-facing summary of the same rules.

## The one rule that matters

> [!IMPORTANT]
> Never edit `./bin/cli` directly. It is a generated artifact — **~240 KB / 9,600 lines**, including the
> inlined Bashly completion engine — built from `cli/*` by `bashly generate`. Reading it burns tens of
> thousands of tokens for no benefit, and any hand
> edit is silently discarded the next time someone runs `pnpm run build:cli`. Edit the authored sources
> in `cli/` instead, then regenerate.

## Files you edit

| Path                                | Responsibility                                                                                           |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `cli/bashly.yml`                    | Schema source of truth: command tree, flags, args, examples, env vars, `version`                         |
| `cli/commands/<group>/<cmd>.sh`     | Command entrypoint (the function Bashly calls for that leaf command); path = command name, spaces → `/`  |
| `cli/lib/*.sh`                      | Shared helper logic (`logging.sh`, `core.sh`, `compose.sh`, `models.sh`, `llm.sh`, `t2i.sh`, `setup.sh`) |
| `cli/lib/validations/validate_*.sh` | Custom argument validators referenced from `bashly.yml` via `validate: <name>`                           |
| `cli/initialize.sh`                 | Pre-parse normalization and bootstrapping (runs before any command)                                      |
| `bashly-settings.yml`               | Bashly settings (`completions: full` enables the native bash/zsh completion engine)                      |

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
   duplicated across command files.
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
   bash -n ./bin/cli
   ./bin/cli --help
   ./bin/cli <group> --help
   ./bin/cli <group> <subgroup> <cmd> --help
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
  `send_completions.sh` lib file) and exposed by `./bin/cli completions [bash|zsh]`
  (`cli/commands/completions.sh`), loaded with `source .bashrc`. Dynamic per-arg completions (e.g.
  listing model names) go on the **arg or flag**, never the command, as `completions: { dynamic: [...] }`
  — each entry is a plain shell command (no `$()` wrapper) printing one candidate per line, run in a
  subshell. See the `models llm download` `model` arg for the pattern
  (`jq -r '.models.[] | .name' models/llm.config.json`). Literal suggestions use `static:`; file/dir
  completion uses `options: [files|directories]`. Smoke-test with `./bin/cli __complete <words...> ""`.

## Checklist: what else to update when the command tree changes

- `bin/README.md` — the command-group table (`## 🗂️ Command groups`) if you added/removed a top-level
  group.
- `AGENTS.md` and `models/README.md` — if the new/changed command is user-facing and those docs mention
  the CLI surface.
- Shell completions — regenerated automatically by `pnpm run build:cli`;
  no separate manual step, but re-run `source .bashrc` in your own shell to pick them up locally.
- Any wizard/skill that shells out to `./bin/cli` (e.g. `.agents/skills/add-model/SKILL.md`) — check
  whether it references the exact subcommand or flag name you changed.

## Error handling

- **`./bin/cli` behaves differently than `cli/` suggests it should.** The generated artifact is out
  of sync with its sources. Run `pnpm run build:cli` and re-test; never hand-patch `./bin/cli` to paper
  over the mismatch.
- **`bash -n ./bin/cli` reports a syntax error.** The line number is inside the generated file, but the
  bug is almost always in the authored `cli/commands/**/*.sh` or `cli/lib/*.sh` file that was
  spliced in at that point — find the corresponding authored file and fix it there, then regenerate.
- **A validator "fails silently" (bad input is accepted, or a good input is rejected with no clear
  reason).** Validator functions communicate failure purely by printing a non-empty string to stdout;
  a validator that does `return 1` without echoing anything looks like success to Bashly. Check that
  every failure path in the `validate_*.sh` file emits an `echo` message before returning.
