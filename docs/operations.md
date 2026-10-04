# ⚙️ Operations

> Day-to-day running of the stack: the `.env` configuration, starting and stopping the cluster, logs, updates,
> extending Compose with your own services, and remote power control.

**Related:** [Installation](installation.md) · [CLI reference](cli.md) · [Networking & security](networking.md) ·
[Models](models.md) · [Monitoring](monitoring.md)

---

## 🧾 Configuration

Runtime configuration lives in `.env`, created from `.env.example` by `setup env`. Defaults are provided for every
non-sensitive value; `.env.example` documents each variable inline and is the source of truth.

| Group                  | Variables                                                                                                                                    | Notes                                                                      |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `llama.cpp` build      | `LLAMA_CPP_REPO`, `LLAMA_CPP_REF`                                                                                                            | Pinned fork + commit; see [LLM serving](llm.md#-speculative-decoding)      |
| `llama.cpp` runtime    | `LLAMA_CPP_BATCH_SIZE`, `LLAMA_CPP_UBATCH_SIZE`, `LLAMA_CPP_CACHE_RAM`, `LLAMA_CPP_MODELS_MAX`, `LLAMA_CPP_PARALLEL`, `LLAMA_CPP_SLOTS_SIZE` | Server-wide knobs; per-model settings live in `llama-cpp/preset.ini`       |
| Idle timeouts          | `LLAMA_CPP_SLEEP_IDLE_SECONDS`, `SD_CPP_SLEEP_IDLE_SECONDS`                                                                                  | `0` disables LLM idle unloading; see [GPU power & VRAM](gpu-management.md) |
| LLM GPU sets           | `LLAMA_CPP_GPUS_STANDALONE`, `LLAMA_CPP_GPUS_SHARED`, `ROCM_VISIBLE_DEVICES` ⚙️                                                              | See [GPU assignment](image-generation.md#gpu-assignment)                   |
| `stable-diffusion.cpp` | `SD_CPP_REPO`, `SD_CPP_REF`, `SD_VISIBLE_DEVICES`                                                                                            | Build pin and the image GPU                                                |
| Active image model     | `SD_CPP_MODEL`, `SD_CPP_DIFFUSION_MODEL`, `SD_CPP_UNCOND_DIFFUSION_MODEL`, `SD_CPP_LLM`, `SD_CPP_VAE`, `SD_CPP_MODEL_ARGS` ⚙️                | Written by `models t2i load`                                               |
| ROCm                   | `ROCM_ARCH`                                                                                                                                  | `gfx1201`; changes only with a new GPU ISA                                 |
| Permissions            | `HOST_UID`, `HOST_GID`, `VIDEO_GID` ⚙️, `RENDER_GID` ⚙️                                                                                      | GPU group IDs synced by `setup env`                                        |
| Network                | `BIND_ADDR` ⚙️                                                                                                                               | Mandatory; see [Networking & security](networking.md)                      |
| Hugging Face           | `HF_TOKEN`                                                                                                                                   | Optional, avoids download rate limits                                      |

⚙️ Managed by the CLI — prefer the owning command over hand edits.

> [!TIP]
> A [Hugging Face token](https://huggingface.co/settings/tokens) is not required, but recommended to avoid rate limits
> when downloading models.

## 🔄 Cluster lifecycle

All commands wrap `docker compose` in the repository root. Commands that accept `[service...]` act on the named
services only; omit them to act on the whole cluster.

| Task                               | Command                                                      |
| ---------------------------------- | ------------------------------------------------------------ |
| Start (detached)                   | `./bin/panther-minor cluster start [service...] [-r]`        |
| Show container status              | `./bin/panther-minor cluster status`                         |
| Restart                            | `./bin/panther-minor cluster restart [service...] [-r] [-v]` |
| Stop                               | `./bin/panther-minor cluster stop [service...] [-v]`         |
| Build images                       | `./bin/panther-minor cluster build [service...] [-n]`        |
| Remove containers, volumes, images | `./bin/panther-minor cluster cleanup`                        |

`-r` / `--remove-orphans` removes containers no longer defined, `-v` / `--volumes` removes named volumes, and
`-n` / `--no-cache` rebuilds without the Docker cache (for example after changing a build pin in `.env`).

> [!CAUTION]
> `--volumes` and `cluster cleanup` delete the named volumes — Open WebUI data (chats, settings), Prometheus history
> and Grafana state included. Model weights in `models/.huggingface` are a bind mount and survive.

## 📜 Logs

```bash
./bin/panther-minor logs <service>            # stream
./bin/panther-minor logs <service> --tail     # print the latest 100 lines once
./bin/panther-minor logs <service> --tail 500 # print the latest 500 lines once
```

Managers and exporters log as `[<service>] LEVEL message {key=value ...}` (e.g. `[llama-manager] INFO …`), filtered
by the `LOG_LEVEL` (`debug`, `info`, `warn`, `error`) set per service in `docker-compose.yml`.

## ⬆️ Updating

```bash
./bin/panther-minor update
```

`update` checks out `main`, fetches and rebases, then switches to the **latest release tag** (detached `HEAD`). After
an update, rebuild and restart so new build pins and configs take effect:

```bash
./bin/panther-minor cluster build
./bin/panther-minor cluster start
```

> [!TIP]
> Record a `models llm bench` baseline before updates that move `LLAMA_CPP_REF`, ROCm or the driver — see
> [Benchmarking](llm.md#-benchmarking).

## 🧩 Extending the cluster

Create `docker-compose.override.yml` in the project root to add services or override configuration; Docker Compose
merges it with the base file automatically. Alternatively, set `COMPOSE_FILE` in `.env` to your own
[compose file list](https://docs.docker.com/compose/how-tos/environment-variables/envvars/#compose_file).

> [!IMPORTANT]
> Always include the base `docker-compose.yml`.

Put extra files, scripts, configuration and assets in `./extra` and mount them into your services as needed. The
directory is kept out of version control.

## 🖲️ Remote power control

[Panther Minor Controller](https://github.com/rozsival/panther-minor-controller) is a companion tool running on a
Raspberry Pi that switches the workstation on, off or reboots it remotely.

---

## ❓ FAQ

### Do I need to restart the cluster after editing `.env`?

Yes — Compose reads `.env` when containers are created. Build pins (`*_REPO`, `*_REF`, `ROCM_ARCH`) additionally need
`cluster build`. Commands that manage `.env` themselves (`models t2i load|unload`) recreate the affected containers.

### Will `cluster stop --volumes` delete my downloaded models?

No. Weights live in the `models/.huggingface` bind mount. It does delete Open WebUI, Prometheus and Grafana data.

### How do I change how long models stay loaded when idle?

Set `LLAMA_CPP_SLEEP_IDLE_SECONDS` in `.env` (default `900`; `0` disables idle unloading) and restart the cluster.

### `update` left me on a detached `HEAD`. Is that wrong?

No. Deployments run from release tags; `update` intentionally switches to the newest one.

### Where do I put a service that should reach the models?

In `docker-compose.override.yml`, attached to the `ai` network, calling `http://llama-manager:8000/v1` or
`http://sd-manager:8000/v1` — never the inference servers directly, or the managers cannot see the activity.
