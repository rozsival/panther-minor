# 🧰 Panther Minor CLI

This directory contains the Panther Minor command-line interface, powered by [Bashly](https://bashly.dev/).

## 📍 At a glance

| Audience           | Use this                                             |
| ------------------ | ---------------------------------------------------- |
| CLI users          | Run `./bin/cli` from the project root                |
| CLI maintainers    | Edit authored sources in `./bin/src/*`               |
| Generated artifact | `./bin/cli` is build output, not the source of truth |

> [!IMPORTANT]
> Do **not** edit `./bin/cli` directly. Update the authored Bashly sources and regenerate it instead.

## 🗂️ Command groups

| Command       | Purpose                                       |
| ------------- | --------------------------------------------- |
| `setup`       | Prepare and secure the host machine           |
| `models`      | Manage supported model downloads and cache    |
| `proxy`       | Work with certificate and proxy-related tasks |
| `cluster`     | Build, start, and stop the AI stack           |
| `logs`        | Inspect service logs                          |
| `update`      | Refresh project assets or dependencies        |
| `completions` | Print shell completion scripts                |

Inspect available commands with:

```bash
./bin/cli --help
./bin/cli <command> --help
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

| Path                          | Responsibility                                    |
| ----------------------------- | ------------------------------------------------- |
| `./bin/src/bashly.yml`        | Command tree, flags, args, examples, and env vars |
| `./bin/src/*_command.sh`      | Command entrypoints                               |
| `./bin/src/lib/*.sh`          | Shared helper logic                               |
| `./bin/src/lib/validations/*` | Custom validations                                |
| `./bin/src/initialize.sh`     | Pre-parse normalization and bootstrapping         |

### Editing rules

- `./bin/src/bashly.yml` is the CLI schema source of truth
- Prefer `bashly generate` **without** `--force`
- `--force` can recreate placeholder command files and overwrite authored command bodies

## 📌 Implementation notes

- Routine status output should use `panther_log_info`, `panther_log_success`, `panther_log_warn`, and
  `panther_log_error`
- Env support is declared per command in `./bin/src/bashly.yml`
- The CLI does not globally load `.env`; commands opt in where needed, while Docker Compose still reads `.env`
- `models download` supports `HF_TOKEN`
- `logs <service>` streams logs, `logs <service> --tail` prints the latest `100` lines once, and
  `logs <service> --tail <n>` prints the latest `<n>` lines once
- `./bin/cli completions` prints the shell completion script for `eval "$(./bin/cli completions)"`

## ✅ Validate after changes

```bash
bash -n ./bin/cli
./bin/cli --help
```
