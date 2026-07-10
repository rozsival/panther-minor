# 🧠 Models

This directory documents the models supported by Panther Minor, split by modality:

- **[`llm/`](#-large-language-models-llm)** — large language models served by `llama.cpp`
- **[`t2i/`](#-text-to-image-models-t2i)** — text-to-image models served by `stable-diffusion.cpp`

Each modality has its own catalog (`config.json` + `config.schema.json`); how to run both side by side is covered in
[Recommended workflows](#-recommended-workflows).

## 📦 Shared model cache

Downloaded weights live in a single shared Hugging Face cache, `models/.huggingface`, mounted into both the
`llama-cpp` and `stable-diffusion-cpp` containers. Each file is stored at its repository-relative path
(`<repository>/<file>`), so:

- a file used by more than one model is downloaded and kept **only once**,
- same-named files from different repositories (such as each LLM's `mmproj-F16.gguf`) never collide.

The cache is managed entirely by the CLI:

```bash
./bin/cli models llm|t2i download <model>   # Fetch only the model's missing files (-f to force re-fetch)
./bin/cli models llm|t2i remove <model>     # Delete only the files the model does not share with another
./bin/cli models prune                      # Reclaim files no config references anymore (also runs after download/remove)
```

## 🧭 Recommended workflows

LLMs and image generation share the same GPUs, so running heavyweight models of both kinds at once contends for VRAM
and can OOM. Pick the workflow that matches your session:

### Everyday: chat with occasional images (no GPU switching)

The chat model plays almost no role in image generation — it merely triggers the image tool call, passes your prompt
down to the image API, and comments on the result. A lightweight model such as `Qwen3.5-2B` does this job perfectly,
and it fits alongside the loaded text-to-image model without VRAM contention.

1. Load a text-to-image model once: `./bin/cli models t2i load <model>`.
2. When you want images, start the chat with a **small LLM** (`Qwen3.5-2B`) instead of a heavyweight one.
3. That's it — no GPU reassignment, no container restarts, and your next heavyweight LLM chat needs no cleanup.

`stable-diffusion.cpp` offloads its weights to RAM between generations, so it only holds VRAM while actually producing
an image — idle VRAM frees itself, no manual unload needed.

### Heavy image sessions: dedicate a GPU

When you generate lots of images, or insist on keeping a heavyweight LLM responsive at the same time, give image
generation a GPU of its own:

```bash
./bin/cli models t2i load --exclusive <model>   # LLMs shrink onto their own GPU(s), sd-server gets a dedicated one
./bin/cli models t2i unload                     # Done: sd-server stops, all GPUs return to the LLMs
```

See [GPU assignment](#gpu-assignment) for how the split works and how to adapt it to your GPU topology.

> [!WARNING]
> Without `--exclusive`, generating images while a heavyweight LLM is under load can still spike VRAM on the shared
> GPUs — prefer not to run both at full tilt at the same time.

---

## 📚 Large language models (`llm/`)

Served by the local `llama.cpp` cluster with an OpenAI-compatible API.

### Supported models

| Model                      | Base                                       | Ctx  | Purpose                                                                                                     |
| -------------------------- | ------------------------------------------ | ---- | ----------------------------------------------------------------------------------------------------------- |
| `Qwen3.6-35B-A3B` 💭 👀 ⚡️ | `unsloth/Qwen3.6-35B-A3B-GGUF`             | 256K | Primary MoE model for complex reasoning, system architecture, and advanced problem-solving across domains   |
| `Qwen3.6-27B` 💭 👀 ⚡️️     | `bottlecapai/ThinkingCap-Qwen3.6-27B-GGUF` | 256K | Versatile dense model optimized for a wide range of tasks, from general reasoning to multimodal processing  |
| `Gemma-4-31B` 💭 👀 ⚡️     | `unsloth/gemma-4-31B-it-GGUF`              | 128K | Heavyweight dense model providing maximum consistency for extensive analysis and text generation tasks      |
| `Qwen3.5-2B` 💭 👀️ ⚡️      | `unsloth/Qwen3.5-2B-GGUF`                  | 8K   | Lightweight dense model optimized for blazing fast inference, rapid scaffolding, and image-generation chats |
| `Qwen3-Embedding-0.6B` 🪶  | `Qwen/Qwen3-Embedding-0.6B-GGUF`           | 8K   | Lightweight embedding model strictly for RAG pipelines                                                      |

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

```bash
./bin/cli models llm list                   # List supported LLMs
./bin/cli models llm download <model>       # Download an LLM into the cache (only missing files)
./bin/cli models llm download <model> -f    # Force re-download of the model's files
./bin/cli models llm remove <model>         # Remove an LLM's unshared files from the cache
./bin/cli models llm load <model>           # Manually load an LLM into the llama.cpp cluster
./bin/cli models llm unload <model>         # Manually unload an LLM from the llama.cpp cluster
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

> [!IMPORTANT]
> Ideogram 4 requires JSON prompts and will most likely fail to generate an image from pure text prompt.
> Read the [Prompting Guide](https://github.com/ideogram-oss/ideogram4/blob/main/docs/prompting.md#prompting-guide) for more information.
> A distilled version is available in `.agents/skills/ideogram4-prompt/GUIDE.md`.
> The `ideogram4-prompt` skill (`.agents/skills/ideogram4-prompt/SKILL.md`) can generate valid JSON prompts from natural language descriptions.

### Configuration

Supported models are defined in `t2i/config.json` (see `t2i/config.schema.json` for the schema):

- **`components`** — the weight files a model needs (diffusion, optional unconditional diffusion, LLM text encoder,
  VAE), each identified by its Hugging Face `repository` and `file`. Models only list the components they use —
  Ideogram 4 has a separate unconditional diffusion model, Qwen-Image does not. Shared components (such as text
  encoders) are kept only once in the [shared cache](#-shared-model-cache).
- **`args`** _(optional)_ — extra `sd-server` flags applied when the model is loaded. This is where per-model sampling
  defaults live (e.g. `--flow-shift` for Qwen-Image); `load` writes them to `SD_CPP_MODEL_ARGS` in `.env`, so the
  tuning switches automatically with the model.

### Management

```bash
./bin/cli models t2i list                   # List supported text-to-image models
./bin/cli models t2i download <model>       # Download a model's components (only missing files)
./bin/cli models t2i download <model> -f    # Force re-download of the model's components
./bin/cli models t2i remove <model>         # Remove a model's unshared components from the cache
./bin/cli models t2i load <model>           # Serve <model> from sd-server (replaces the loaded model)
./bin/cli models t2i load -e <model>        # Same, but on a dedicated GPU (see GPU assignment)
./bin/cli models t2i unload                 # Stop sd-server (returns dedicated GPUs to the LLMs)
```

### Loading and switching

`sd-server` loads exactly **one** text-to-image model per process, so only one is ever resident. `load` rewrites the
active-model variables in `.env` and recreates the single `stable-diffusion-cpp` container, replacing whatever was
loaded before — switching never leaves two models in VRAM.

Switching is entirely a CLI operation. `sd-server` serves whatever model it currently has loaded and ignores the model
id in the request, so **Open WebUI needs no changes**: leave its image model field at `default`. You never touch the
admin image settings when switching.

> [!NOTE]
> Because the requested model id plays no role, `IMAGE_GENERATION_MODEL` (`${SD_CPP_MODEL}` in `.env`) is just a label.
> The Images panel in Open WebUI lists only the currently-loaded model, since that is all `sd-server` reports at
> `/v1/models`.

### GPU assignment

By default, `load` only swaps the model — the GPU assignment is left untouched and the LLMs keep all GPUs. This is the
right mode for the [everyday workflow](#everyday-chat-with-occasional-images-no-gpu-switching).

For [heavy image sessions](#heavy-image-sessions-dedicate-a-gpu), `load --exclusive` hands image generation a GPU of
its own so the two stacks never contend for the same VRAM:

- **`load --exclusive`** shrinks the LLMs to `LLAMA_CPP_GPUS_SHARED` (writing it to `ROCM_VISIBLE_DEVICES` in `.env`)
  and recreates `llama-cpp`, freeing `SD_VISIBLE_DEVICES` for `sd-server` alone.
- **`unload`** stops `sd-server` and — only if a previous `--exclusive` load shrank the LLMs — restores them to
  `LLAMA_CPP_GPUS_STANDALONE` (all GPUs) and recreates `llama-cpp` so it reclaims the freed GPU.

The GPU sets live in `.env` (see `.env.example`) — edit them to match your GPU topology:

| Variable                    | Default | Meaning                                                            |
| --------------------------- | ------- | ------------------------------------------------------------------ |
| `ROCM_VISIBLE_DEVICES`      | `0,1`   | Active GPU set the LLMs run on (managed by `load -e` / `unload`)   |
| `LLAMA_CPP_GPUS_STANDALONE` | `0,1`   | GPUs the LLMs use outside exclusive mode (all GPUs)                |
| `LLAMA_CPP_GPUS_SHARED`     | `0`     | GPUs the LLMs shrink to while exclusive mode is active             |
| `SD_VISIBLE_DEVICES`        | `1`     | GPU(s) `sd-server` runs on — dedicated to it during exclusive mode |

> [!NOTE]
> `load --exclusive` and the `unload` that follows it restart `llama-cpp`, so any resident LLMs reload lazily on the
> next request. This is the price of a clean GPU handoff — switch modes per work session, not per image.
