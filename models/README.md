# 🧠 Models

This directory documents the models supported by Panther Minor, split by modality:

- **`llm/`** — large language models served by `llama.cpp` (`config.json`, `config.schema.json`, `preset.ini`, coding-agent presets)
- **`t2i/`** — text-to-image models served by `stable-diffusion.cpp` (`config.json`, `config.schema.json`)

Downloaded weights live in a single shared Hugging Face cache, `models/.huggingface`, mounted into both the
`llama-cpp` and `stable-diffusion-cpp` containers. Each file is stored at its repository-relative path
(`<repository>/<file>`), so a file used by more than one model — for example the Qwen3-VL-8B encoder shared by both
text-to-image models — is downloaded and kept only once, while same-named files from different repositories (such as
each LLM's `mmproj-F16.gguf`) never collide. `download` fetches only missing files (pass `--force` to re-fetch),
`remove` deletes only the files a model does not share with another, and `./bin/cli models prune` reclaims any file no
config references anymore (it also runs automatically after every `download`/`remove`).

---

## 📚 Large language models (`llm/`)

Served by the local `llama.cpp` cluster with an OpenAI-compatible API.

### Supported models

| Model                      | Base                             | Ctx  | Purpose                                                                                                    |
| -------------------------- | -------------------------------- | ---- | ---------------------------------------------------------------------------------------------------------- |
| `Qwen3.6-35B-A3B` 💭 👀 ⚡️ | `unsloth/Qwen3.6-35B-A3B-GGUF`   | 256K | Primary MoE model for complex reasoning, system architecture, and advanced problem-solving across domains  |
| `Qwen3.6-27B` 💭 👀 ⚡️️     | `unsloth/Qwen3.6-27B-GGUF`       | 256K | Versatile dense model optimized for a wide range of tasks, from general reasoning to multimodal processing |
| `Gemma-4-31B` 💭 👀 ⚡️     | `unsloth/gemma-4-31B-it-GGUF`    | 128K | Heavyweight dense model providing maximum consistency for extensive analysis and text generation tasks     |
| `Qwen3.5-2B` 💭 👀️ ⚡️      | `unsloth/Qwen3.5-2B-GGUF`        | 8K   | Lightweight dense model optimized for blazing fast inference and rapid scaffolding                         |
| `Qwen3-Embedding-0.6B` 🪶  | `Qwen/Qwen3-Embedding-0.6B-GGUF` | 8K   | Lightweight embedding model strictly for RAG pipelines                                                     |

Legend:

- 💭 — thinking preset available
- 👀 — multimodal capabilities (vision encoder enabled)
- ⚡️ — speculative decoding with Multi Token Prediction (MTP) enabled
- 🪶 — embedding-only model (no text generation)

### Configuration

Supported models are defined in `llm/config.json` (see `llm/config.schema.json` for the schema). At runtime, the
`llama-cpp` service runs in
[router mode](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#using-multiple-models) and serves models
through `llm/preset.ini`
[presets](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#model-presets).

### Management

Use the Panther Minor CLI to manage LLMs in the shared `models/.huggingface` cache:

```bash
./bin/cli models llm list                   # List supported LLMs
./bin/cli models llm download <model>       # Download an LLM into the cache (only missing files)
./bin/cli models llm download <model> -f    # Force re-download of the model's files
./bin/cli models llm remove <model>         # Remove an LLM's unshared files from the cache
./bin/cli models llm load <model>           # Manually load an LLM into the llama.cpp cluster
./bin/cli models llm unload <model>         # Manually unload an LLM from the llama.cpp cluster
./bin/cli models prune                      # Delete cached files no config references anymore
```

### Coding agent presets

Presets that connect external coding agents to the local LLM API live in `llm/`.

#### OpenCode

Use `llm/opencode.json` as the recommended [configuration](https://opencode.ai/docs/config/) for OpenCode:

```bash
cp llm/opencode.json ~/.config/opencode/opencode.json
```

> [!IMPORTANT]
> Replace `<domain>` in `opencode.json` with your actual domain so OpenCode can connect to the API correctly.

#### Pi

Use `llm/pi/models.json` and `llm/pi/settings.json` as the recommended [settings](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#settings) for Pi:

```bash
cp llm/pi/*.json ~/.pi/agent/
```

> [!IMPORTANT]
> Replace `<domain>` in `models.json` with your actual domain so Pi can connect to the API correctly.

---

## 🎨 Text-to-image models (`t2i/`)

Served by [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)'s `sd-server`, exposing an
OpenAI-compatible image API on port `8001`.

### Supported models

| Model             | Base                           | Notes                                                                                              |
| ----------------- | ------------------------------ | -------------------------------------------------------------------------------------------------- |
| `Ideogram-4`      | `leejet/ideogram-4-GGUF`       | Strong prompt adherence and text rendering; uses a Qwen3-VL-8B encoder + Flux2 VAE                 |
| `Qwen-Image-2512` | `unsloth/Qwen-Image-2512-GGUF` | Photorealistic generation and strong text rendering (Q4_0); Qwen2.5-VL-7B encoder + Qwen-Image VAE |

### Configuration

Supported models are defined in `t2i/config.json` (see `t2i/config.schema.json` for the schema). Each model lists the
weight `components` it needs (diffusion, optional unconditional diffusion, LLM text encoder, VAE), each identified by its
Hugging Face `repository` and `file`. Components are stored in the shared `models/.huggingface` cache at
`<repository>/<file>`, so a component shared with another model (such as the Qwen3-VL-8B encoder used by both
text-to-image models) is kept only once. Models only list the components they use — Ideogram 4 has a separate
unconditional diffusion model, Qwen-Image does not.

A model may also define an optional `args` array of extra `sd-server` flags applied when it is loaded. This is where
per-model sampling defaults live, `load` writes these to `SD_CPP_MODEL_ARGS` in `.env`, so the
tuning switches automatically with the model.

### Management

Use the Panther Minor CLI to manage text-to-image models in the shared `models/.huggingface` cache:

```bash
./bin/cli models t2i list                   # List supported text-to-image models
./bin/cli models t2i download <model>       # Download a model's components (only missing files)
./bin/cli models t2i download <model> -f    # Force re-download of the model's components
./bin/cli models t2i remove <model>         # Remove a model's unshared components from the cache
./bin/cli models t2i load <model>           # Serve <model> from sd-server (replaces the loaded model)
./bin/cli models t2i unload                 # Stop sd-server to free its GPU VRAM
./bin/cli models prune                      # Delete cached files no config references anymore
```

> [!IMPORTANT]
> `sd-server` loads exactly **one** text-to-image model per process, so only one is ever resident in VRAM. `load`
> rewrites the active-model variables in `.env` and recreates the single `stable-diffusion-cpp` container, replacing the
> previously loaded model.

### Switching the loaded model

Switching is entirely a CLI operation — `models t2i load <model>` recreates `sd-server` with the new model and that is
all. `sd-server` serves whatever model it currently has loaded and ignores the model id in the request, so **Open WebUI
needs no changes**: leave its image model field at `default`. You never touch the admin image settings when switching.

> [!NOTE]
> Because the requested model id plays no role, `IMAGE_GENERATION_MODEL` (`${SD_CPP_MODEL}` in `.env`) is just a label.
> The Images panel in Open WebUI lists only the currently-loaded model, since that is all `sd-server` reports at
> `/v1/models`.
