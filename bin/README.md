# `bin`

Panther Minor CLI lives here. Powered by [Bashly](https://bashly.dev/).

- Users run `./cli`
- Maintainers edit `./src/*`
- `./cli` is generated output, not the source of truth

## Current command groups

- `setup`
- `models`
- `proxy`
- `cluster`
- `logs`
- `update`
- `completions`

Inspect them with:

```bash
./cli --help
./cli <command> --help
```

Load completions with:

```bash
source .bashrc
```

## Edit flow

Update the authored Bashly sources, then regenerate:

```bash
bashly generate
```

Important:

- Edit `./src/bashly.yml` for commands, flags, args, examples, and env vars
- Edit `./src/*_command.sh` for command entrypoints
- Edit `./src/lib/panther.sh` for shared logic
- Edit `./src/lib/validations/*` for custom validations
- Edit `./src/initialize.sh` for pre-parse normalization/bootstrapping
- DO NOT read/write `./cli`, it is generated
- Prefer `bashly generate` without `--force`; `--force` can recreate placeholder command files and overwrite authored
  bodies

## Notes

- `./src/bashly.yml` is the CLI schema source of truth
- Most shared implementation lives in `./src/lib/panther.sh`
- Routine status output should use `panther_log_info`, `panther_log_success`, `panther_log_warn`, and
  `panther_log_error`
- Env support is declared per command in `./src/bashly.yml`
- The CLI does not globally load `.env`; commands opt in where needed, while Docker Compose still reads `.env`
- `models download` supports `HF_TOKEN`
- `logs <service>` streams logs, `logs <service> --tail` prints the latest `100` lines once, and
  `logs <service> --tail <n>` prints the latest `<n>` lines once
- `./cli completions` prints the shell completion script for `eval "$(./cli completions)"`

## Validate after changes

```bash
bash -n ./cli
./cli --help
```
