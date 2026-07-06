# 🧠 Models

This directory documents the models supported by Panther Minor. It is split by modality:

- **`llm/`** — large language models served by `llama.cpp` (`config.json`, `config.schema.json`, `preset.ini`, coding-agent presets)
- **`t2i/`** — text-to-image models served by `stable-diffusion.cpp` (`config.json`, `config.schema.json`)

Downloaded weights live in a per-modality Hugging Face cache: `models/llm/.huggingface` and `models/t2i/.huggingface`.

## 📚 Large language models

Served by the local `llama.cpp` cluster with an OpenAI-compatible API.

| Model                      | Base                             | Ctx  | Purpose                                                                                                    |
| -------------------------- | -------------------------------- | ---- | ---------------------------------------------------------------------------------------------------------- |
| `Qwen3.6-35B-A3B` 💭 👀 ⚡️ | `unsloth/Qwen3.6-35B-A3B-GGUF`   | 256K | Primary MoE model for complex reasoning, system architecture, and advanced problem-solving across domains  |
| `Qwen3.6-27B` 💭 👀 ⚡️️     | `unsloth/Qwen3.6-27B-GGUF`       | 256K | Versatile dense model optimized for a wide range of tasks, from general reasoning to multimodal processing |
| `Gemma-4-31B` 💭 👀 ⚡️     | `unsloth/gemma-4-31B-it-GGUF`    | 128K | Heavyweight dense model providing maximum consistency for extensive analysis and text generation tasks     |
| `Qwen3.5-2B` 💭 👀️ ⚡️      | `unsloth/Qwen3.5-2B-GGUF`        | 8K   | Lightweight dense model optimized for blazing fast inference and rapid scaffolding                         |
| `Qwen3-Embedding-0.6B` 🪶  | `Qwen/Qwen3-Embedding-0.6B-GGUF` | 8K   | Lightweight embedding model strictly for RAG pipelines                                                     |

### Legend

- 💭 — thinking preset available
- 👀 — multimodal capabilities (vision encoder enabled)
- ⚡️ — speculative decoding with Multi Token Prediction (MTP) enabled
- 🪶 — embedding-only model (no text generation)

## ⚙️ How model configuration works

Supported models are defined in `llm/config.json`. See `llm/config.schema.json` for the configuration schema.

At runtime, the `llama-cpp` service runs in
[router mode](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#using-multiple-models) and serves models
through `preset.ini`
[presets](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#model-presets).

## 🛠️ Model management

Use the Panther Minor CLI to manage LLMs in the `models/llm/.huggingface` cache:

```bash
./bin/cli models llm list             # List supported LLMs
./bin/cli models llm download <model> # Download an LLM into the cache
./bin/cli models llm remove <model>   # Remove an LLM from the cache
./bin/cli models llm load <model>     # Manually load an LLM into the llama.cpp cluster
./bin/cli models llm unload <model>   # Manually unload an LLM from the llama.cpp cluster
```

## 🎨 Text-to-image models

Panther Minor also serves text-to-image generation through
[stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)'s `sd-server`, exposing an OpenAI-compatible
image API on port `8001`.

| Model        | Base                     | Notes                                                                              |
| ------------ | ------------------------ | ---------------------------------------------------------------------------------- |
| `ideogram-4` | `leejet/ideogram-4-GGUF` | Strong prompt adherence and text rendering; uses a Qwen3-VL-8B encoder + Flux2 VAE |

Text-to-image models are defined in `t2i/config.json` (see `t2i/config.schema.json` for the schema). Each model lists
the weight `components` it needs (diffusion, unconditional diffusion, LLM text encoder, VAE), which may come from
different Hugging Face repositories and are downloaded into a single per-model directory in the
`models/t2i/.huggingface` cache.

Manage text-to-image models with the Panther Minor CLI:

```bash
./bin/cli models t2i list             # List supported text-to-image models
./bin/cli models t2i download <model> # Download a text-to-image model into the cache
./bin/cli models t2i remove <model>   # Remove a text-to-image model from the cache
```

## 💻 Coding Agent Presets

### OpenCode

Use `llm/opencode.json` as the recommended [configuration](https://opencode.ai/docs/config/) for OpenCode:

```bash
cp llm/opencode.json ~/.config/opencode/opencode.json
```

> [!IMPORTANT]
> Replace `<domain>` in `opencode.json` with your actual domain so OpenCode can connect to the API correctly.

### Pi

Use `llm/pi/models.json` and `llm/pi/settings.json` as the recommended [settings](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#settings) for Pi:

```bash
cp llm/pi/*.json ~/.pi/agent/
```

> [!IMPORTANT]
> Replace `<domain>` in `models.json` with your actual domain so Pi can connect to the API correctly.
