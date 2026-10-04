# 🧰 Panther Minor CLI

This directory contains the Panther Minor command-line interface, powered by [Bashly](https://bashly.dev/).

## 📍 At a glance

| Audience           | Use this                                                       |
| ------------------ | -------------------------------------------------------------- |
| CLI users          | Run `./bin/panther-minor` from the project root                |
| CLI maintainers    | Edit authored sources in `./cli/*`                             |
| Generated artifact | `./bin/panther-minor` is build output, not the source of truth |

> [!IMPORTANT]
> Do **not** edit `./bin/panther-minor` directly. Update the authored Bashly sources and regenerate it instead.

## 🗂️ Command groups

| Command       | Purpose                                                 |
| ------------- | ------------------------------------------------------- |
| `setup`       | Prepare and secure the host machine                     |
| `models`      | Manage model downloads, cache, and throughput baselines |
| `proxy`       | Work with certificate and proxy-related tasks           |
| `cluster`     | Build, start, and stop the AI stack                     |
| `logs`        | Inspect service logs                                    |
| `update`      | Refresh project assets or dependencies                  |
| `completions` | Print shell completion scripts                          |

Inspect available commands with:

```bash
./bin/panther-minor --help
./bin/panther-minor <command> --help
```

Load shell completions with:

```bash
source .bashrc
```

## ✍️ Maintainer workflow

After changing the authored CLI sources, regenerate the CLI:

```bash
pnpm run build:cli
```

### Edit the right files

| Path                      | Responsibility                                                                  |
| ------------------------- | ------------------------------------------------------------------------------- |
| `./cli/bashly.yml`        | Command tree, flags, args, examples, and env vars                               |
| `./cli/commands/**/*.sh`  | Command entrypoints (`models llm bench` → `./cli/commands/models/llm/bench.sh`) |
| `./cli/lib/*.sh`          | Shared helper logic                                                             |
| `./cli/lib/validations/*` | Custom validations                                                              |
| `./cli/initialize.sh`     | Pre-parse normalization and bootstrapping                                       |
| `./bashly-settings.yml`   | Bashly settings (`completions: full`)                                           |

### Editing rules

- `./cli/bashly.yml` is the CLI schema source of truth
- Prefer `bashly generate` **without** `--force`
- `--force` can recreate placeholder command files and overwrite authored command bodies

## 📌 Implementation notes

- Routine status output should use `panther_log_info`, `panther_log_success`, `panther_log_warn`, and
  `panther_log_error`
- Env support is declared per command in `./cli/bashly.yml`
- The CLI does not globally load `.env`; commands opt in where needed, while Docker Compose still reads `.env`
- `models download` supports `HF_TOKEN`
- `logs <service>` streams logs, `logs <service> --tail` prints the latest `100` lines once, and
  `logs <service> --tail <n>` prints the latest `<n>` lines once
- `./bin/panther-minor completions [bash|zsh]` prints the shell completion script (default `bash`) for
  `eval "$(./bin/panther-minor completions)"`; completions are generated natively by Bashly 2 (`completions: full` in
  `./bashly-settings.yml`)
- Per-argument completions live on the arg in `./cli/bashly.yml` as `completions: { static | dynamic | options }`

## ✅ Validate after changes

```bash
bash -n ./bin/panther-minor
./bin/panther-minor --help
```
