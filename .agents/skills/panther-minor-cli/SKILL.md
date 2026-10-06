---
name: panther-minor-cli
description: >
  Operate a Panther Minor workstation through its CLI (`panther-minor` / `./bin/panther-minor`): start, stop,
  restart or rebuild the Compose cluster, check container status, tail service logs, load/unload/bench LLM
  presets, download/remove/prune model weights, load/unload text-to-image models, renew certificates, run
  single host setup steps, and update the checkout to the latest release. Use whenever the user asks to
  "start the stack", "restart llama-cpp", "load Qwen…", "free VRAM", "what's running", "show me the logs",
  "download a model", "switch the image model", "update the server" — even if they never name the CLI.
  Not for changing the CLI's own code or flags (that is `cli-command`) or for preset tuning loops
  (`tune-preset`).
---

You are operating a live AI workstation on someone's behalf. Every command here acts on real GPUs, real
weights and services other people may be using, so the job is: pick the right command, run it where the
stack actually lives, never hang on a prompt, and never trade the user's data for convenience.

## Where to run it

The CLI drives `docker compose` in the repository root and talks to `llama-manager` at
`https://localhost:8000`, so stack commands only work **on the Panther host** (Ubuntu, AMD GPUs). Help,
`list` and completions work anywhere.

1. Probe: `uname -s` first. `Darwin`, or no Docker → you are on a dev machine; run stack commands over SSH.
   On Linux, `panther-minor cluster status` (or `./bin/panther-minor cluster status` from the repo root):
   - a container table → you are on the host; run commands directly.
   - `required variable BIND_ADDR is missing` → host whose Tailscale address was never recorded (see
     [Reading failures](#reading-failures)).
2. Over SSH: SSH listens on port `2222` with key-only auth. If `~/.ssh/config` has an alias that clearly
   points at the workstation, use it without asking for read-only commands and for whatever the user
   asked you to do; otherwise ask the user for `user@host` once. `~/.local/bin` (where `install` puts the
   symlink) is only on the `PATH` of a login shell, so wrap the call:
   ```bash
   ssh -n -p 2222 <user>@<host> 'bash -lc "panther-minor cluster status"'
   ```
   `-n` gives the remote command an empty stdin, for the reason in
   [Running without a terminal](#running-without-a-terminal). `sudo` over SSH needs a password prompt you
   cannot answer — hand those commands to the user (see below).

Invoke `panther-minor` if it is on the `PATH`, else `./bin/panther-minor` from the repository root. Both
resolve the repository through the symlink, so the working directory does not matter.

> [!IMPORTANT]
> Never read `bin/panther-minor`. It is a ~10k-line generated Bashly artifact; reading it burns tens of
> thousands of tokens. `panther-minor <command> --help` is the cheap ground truth for flags, and
> `docs/cli.md` is the full reference.

## Names: preset vs model

| Argument            | Comes from                                    | Used by                                    |
| ------------------- | --------------------------------------------- | ------------------------------------------ |
| LLM **preset**      | `[section]` headers in `llama-cpp/preset.ini` | `models llm load`, `unload`, `bench`       |
| LLM **model**       | `name` in `models/llm.config.json`            | `models llm download`, `remove`            |
| Text-to-image model | `name` in `models/t2i.config.json`            | `models t2i download`, `remove`, `load`    |
| Compose **service** | `docker-compose.yml`                          | `cluster start/stop/restart/build`, `logs` |

Preset and model names usually match but are separate lists. Get the exact candidates instead of guessing
from the user's phrasing ("the flash model", "qwen 27"):

```bash
panther-minor __complete models llm load ""      # loadable presets
panther-minor __complete models llm download ""  # downloadable LLMs (same as `models llm list`)
panther-minor __complete models t2i load ""      # text-to-image models
panther-minor __complete logs ""                 # services (needs a working compose config, i.e. the host)
```

Ignore the trailing `:options=` line. Names are case-sensitive; validators reject anything else with the
valid list in the error.

Map the user's phrasing onto exactly one candidate; if it fits several ("qwen 3.8") or none ("the old
one" when only one version exists), ask instead of picking.

## Running without a terminal

You have no TTY, so four behaviours matter:

- **Always give the CLI an empty stdin:** append `</dev/null` locally, use `ssh -n` remotely. Prompts read
  stdin; at end-of-file they fail immediately, but a runner that leaves stdin open as an idle pipe makes them
  block forever instead. With the redirect the behaviour below is deterministic.
- **Confirmation prompts fail closed.** `models llm|t2i remove`, `models prune`, the orphan sweep at the end
  of `models llm|t2i download`, and every `setup <step>` print what they are about to touch, then
  `[CONFIRM] …`, then **exit 1 with no further message** on empty stdin. Nothing was deleted — which makes
  the plain invocation a safe preview (`panther-minor models llm remove <model> </dev/null`). Show the user
  that list, get an explicit yes for it, then re-run with `PANTHER_CONFIRMED=1` prefixed (for `sudo`:
  `sudo PANTHER_CONFIRMED=1 panther-minor …`). The user saying "delete X" is the request, not the yes to the
  file list; never set the variable pre-emptively — it is the only thing standing between a typo and deleted
  weights.
- **`logs <service>` follows forever.** Always pass `--tail <n>` (`logs llama-manager --tail 200`).
- **Some commands are interactive by design** — `setup all` (reads five values and a final y/N),
  `proxy certbot` (waits for you to create a DNS record and press Enter), and anything needing `sudo` over
  SSH. Give the user the exact command to run themselves and stop.

Long runners — `cluster build` (compiles llama.cpp for ROCm: many minutes), `models llm|t2i download`
(tens of GB), `models llm bench` (minutes; longer with `--loads`), `models llm load` of a large model — need
a generous timeout or a background job, not the default.

## Risk tiers

Run read-only commands freely. State-changing commands are fine when the user asked for that outcome; say
what else they disrupt. Destructive commands need the user's explicit go-ahead for that exact command,
even if a broader request implied it.

| Tier           | Commands                                                                                                                                                                                                                                                                                                                         |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Read-only      | `--help`, `--version`, `cluster status`, `logs <svc> --tail n`, `models llm list`, `models t2i list`, `__complete …`, `completions`                                                                                                                                                                                              |
| State-changing | `cluster start/stop/restart/build` (without `-v`), `models llm load/unload`, `models llm bench`, `models t2i load/unload`, `models llm/t2i download`, `proxy renew-ssl`, `proxy setup-cron`, `install`, `update`                                                                                                                 |
| Destructive    | `cluster stop -v`, `cluster restart -v` (delete named volumes: Open WebUI chats/users, Prometheus history, Grafana state), `cluster cleanup` (`down -v --rmi all`: all of that plus every image, so the next start rebuilds llama.cpp), `models llm/t2i remove`, `models prune`, `download --force` (deletes before re-fetching) |
| Hand to user   | `setup …` (root; `setup all` interactive), `proxy certbot`                                                                                                                                                                                                                                                                       |

Side effects worth stating before you run:

- `cluster stop|restart` without services acts on the **whole** stack; pass service names to scope it
  (`cluster restart llama-cpp llama-manager`).
- `models t2i load --exclusive` and `models t2i unload` (after an exclusive load) rewrite `.env` and
  recreate `llama-cpp` — every loaded LLM and in-flight request is dropped.
- `models t2i load` (shared) rewrites the `SD_CPP_*` keys in `.env` and recreates `stable-diffusion-cpp`.
- `models llm load` of a large model (`largeModelIds` in `llama-cpp/models.js`) makes `llama-manager` unload
  any other loaded large model first; idle models also unload themselves after `LLAMA_CPP_SLEEP_IDLE_SECONDS`,
  so "it was loaded a minute ago" is normal.
- `models llm bench --loads N>1` restarts `llama-cpp` between loads and appends to `models/bench.log`. For
  anything beyond a one-off number, use the `tune-preset` skill.
- `update` runs `git checkout main`, pulls, then detaches `HEAD` at the latest release tag. Run it only on
  the host's deployment checkout, never on a development clone with work in progress. Follow it with
  `cluster build` and `cluster start` when the release changed images.

## Recipes

**What is running / loaded?**

```bash
panther-minor cluster status
curl -sk https://localhost:8000/models | jq -r '.data[] | "\(.id)\t\(.status.value)"'   # LLM residency
```

The manager counts model-list requests as activity, so polling this in a loop postpones idle unloading.

**What is downloaded?** (run in the repository root on the host; `remove`'s preview also lists files)

```bash
jq -r '.models[] | .name as $n | .components[] | "\($n)\t\(.repository)/\(.file)"' models/llm.config.json models/t2i.config.json |
  while IFS=$'\t' read -r name file; do
    [[ -f "models/.huggingface/$file" ]] && state=present || state=missing
    printf '%s\t%s\t%s\n' "$name" "$state" "$file"
  done
du -sh models/.huggingface/*/*
```

A preset is loadable only if every component of its model is `present`. Over SSH, find the repository root
with `dirname "$(dirname "$(readlink -f ~/.local/bin/panther-minor)")"`.

**Load / swap an LLM**

```bash
panther-minor models llm load <preset>      # blocks until resident; large models take minutes
panther-minor models llm unload <preset>    # frees its VRAM
```

A load that fails with an HTTP error mentioning a missing file means the weights are absent →
`models llm download <model>`, then load again.

**Download weights** (reads `HF_TOKEN` from the shell or `.env`; skips files already present)

```bash
panther-minor models llm download <model>
panther-minor models t2i download <model>
```

If it ends on `[CONFIRM] Delete these N file(s)…` with exit 1, the download itself succeeded; only the
orphan sweep was declined — report the listed files and ask before re-running `models prune` with
`PANTHER_CONFIRMED=1`.

**Image generation**

```bash
panther-minor models t2i load <model>               # shares GPUs with the LLMs
panther-minor models t2i load --exclusive <model>   # dedicates a GPU; restarts llama-cpp
panther-minor models t2i unload                     # stops sd-server, returns GPUs to the LLMs
```

**Restart a misbehaving service and check it came back**

```bash
panther-minor cluster restart <service>
panther-minor cluster status
panther-minor logs <service> --tail 100
```

**Deploy the latest release** (host only, user-approved)

```bash
panther-minor update
panther-minor cluster build          # long; add -n/--no-cache only after changing a build pin in .env
panther-minor cluster start
panther-minor cluster status
```

## Reading failures

| Output                                                    | Meaning → action                                                                                                                           |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `required variable BIND_ADDR is missing a value`          | Not the host, or Tailscale was down at `setup env`. On the host: user runs `sudo tailscale up`, then `sudo ./bin/panther-minor setup env`. |
| `cannot reach llama-manager at https://localhost:8000`    | Stack down or proxy not bound → `cluster status`, then `cluster start` / `logs proxy --tail 100`.                                          |
| `validation error in MODEL: must be one of: …`            | Wrong preset/model name for that command → pick from the printed list.                                                                     |
| `Text-to-image model '…' is not downloaded`               | `models t2i download <model>` first.                                                                                                       |
| `HTTP 4xx/5xx: …` from `load`                             | Manager or llama-server refused → `logs llama-cpp --tail 200` and `logs llama-manager --tail 200`.                                         |
| `[CONFIRM] …` then exit 1                                 | Prompt declined for lack of a TTY; nothing deleted → confirm with the user, re-run with `PANTHER_CONFIRMED=1`.                             |
| `This command must be run as root (use sudo).`            | A `setup` step → hand it to the user.                                                                                                      |
| `Run install as the user who uses the CLI, not with sudo` | Re-run `install` without `sudo`.                                                                                                           |

When reporting back, give the command you ran, its exit code, and the lines that matter (the `[OK]`/`[ERROR]`
line, the status row, the bench summary) — not the whole scroll.
