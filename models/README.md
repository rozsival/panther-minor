# 🧠 Models

This directory documents the models supported by Panther Minor, split by modality:

- **`llm/`** — large language models served by `llama.cpp` (`config.json`, `config.schema.json`, `preset.ini`, coding-agent presets)
- **`t2i/`** — text-to-image models served by `stable-diffusion.cpp` (`config.json`, `config.schema.json`)

Downloaded weights live in a per-modality Hugging Face cache: `models/llm/.huggingface` and `models/t2i/.huggingface`.

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

Use the Panther Minor CLI to manage LLMs in the `models/llm/.huggingface` cache:

```bash
./bin/cli models llm list             # List supported LLMs
./bin/cli models llm download <model> # Download an LLM into the cache
./bin/cli models llm remove <model>   # Remove an LLM from the cache
./bin/cli models llm load <model>     # Manually load an LLM into the llama.cpp cluster
./bin/cli models llm unload <model>   # Manually unload an LLM from the llama.cpp cluster
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
| `ideogram-4`      | `leejet/ideogram-4-GGUF`       | Strong prompt adherence and text rendering; uses a Qwen3-VL-8B encoder + Flux2 VAE                 |
| `qwen-image-2512` | `unsloth/Qwen-Image-2512-GGUF` | Photorealistic generation and strong text rendering (Q4_0); Qwen2.5-VL-7B encoder + Qwen-Image VAE |

### Configuration

Supported models are defined in `t2i/config.json` (see `t2i/config.schema.json` for the schema). Each model lists the
weight `components` it needs (diffusion, optional unconditional diffusion, LLM text encoder, VAE), which may come from
different Hugging Face repositories and are downloaded into a single per-model directory in the `models/t2i/.huggingface`
cache. Models only list the components they use — Ideogram 4 has a separate unconditional diffusion model, Qwen-Image
does not.

### Management

Use the Panther Minor CLI to manage text-to-image models in the `models/t2i/.huggingface` cache:

```bash
./bin/cli models t2i list             # List supported text-to-image models
./bin/cli models t2i download <model> # Download a text-to-image model into the cache
./bin/cli models t2i remove <model>   # Remove a text-to-image model from the cache
./bin/cli models t2i load <model>     # Serve <model> from sd-server (replaces the loaded model)
./bin/cli models t2i unload           # Stop sd-server to free its GPU VRAM
```

> [!IMPORTANT]
> `sd-server` loads exactly **one** text-to-image model per process, so only one is ever resident in VRAM. `load`
> rewrites the active-model variables in `.env` and recreates the single `stable-diffusion-cpp` container, replacing the
> previously loaded model. After switching, set Open WebUI's image model (admin image settings) to match so chat image
> generation targets the loaded model.
