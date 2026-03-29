# `bin`

Panther Minor CLI lives here, runs from root. Powered by [Bashly](https://bashly.dev/).

- Users run `./bin/cli`
- Maintainers edit `./bin/src/*`
- `./bin/cli` is generated output, not the source of truth

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
./bin/cli --help
./bin/cli <command> --help
```

Load completions with:

```bash
source .bashrc
```

## Edit flow

Update the authored Bashly sources, then regenerate:

```bash
pnpm run build:cli
```

Important:

- Edit `./bin/src/bashly.yml` for commands, flags, args, examples, and env vars
- Edit `./bin/src/*_command.sh` for command entrypoints
- Edit `./bin/src/lib/*.sh` for shared logic
- Edit `./bin/src/lib/validations/*` for custom validations
- Edit `./bin/src/initialize.sh` for pre-parse normalization/bootstrapping
- DO NOT read/write `./bin/cli`, it is generated
- Prefer `bashly generate` without `--force`; `--force` can recreate placeholder command files and overwrite authored
  bodies

## Notes

- `./bin/src/bashly.yml` is the CLI schema source of truth
- Routine status output should use `panther_log_info`, `panther_log_success`, `panther_log_warn`, and
  `panther_log_error`
- Env support is declared per command in `./bin/src/bashly.yml`
- The CLI does not globally load `.env`; commands opt in where needed, while Docker Compose still reads `.env`
- `models download` supports `HF_TOKEN`
- `logs <service>` streams logs, `logs <service> --tail` prints the latest `100` lines once, and
  `logs <service> --tail <n>` prints the latest `<n>` lines once
- `./bin/cli completions` prints the shell completion script for `eval "$(./bin/cli completions)"`

## Validate after changes

```bash
bash -n ./bin/cli
./bin/cli --help
```
