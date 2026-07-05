# 🧠 Models

This directory documents the model presets supported by Panther Minor and how they are wired into the local
`llama.cpp` cluster.

## 📚 Supported models

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

Supported models are defined in `config.json`. See `schema.json` for the configuration schema.

At runtime, the `llama-cpp` service runs in
[router mode](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#using-multiple-models) and serves models
through `preset.ini`
[presets](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#model-presets).

## 🛠️ Model management

Use the Panther Minor CLI to manage models in the `.huggingface` cache:

```bash
./bin/cli models list             # List supported models
./bin/cli models download <model> # Download a model into the .huggingface cache
./bin/cli models remove <model>   # Remove a model from the .huggingface cache
./bin/cli models load <model>     # Manually load a model into the llama.cpp cluster
./bin/cli models unload <model>   # Manually unload a model from the llama.cpp cluster
```

## 🎨 Image models

Panther Minor also serves text-to-image generation through
[stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)'s `sd-server`, exposing an OpenAI-compatible
image API on port `8001`.

| Model        | Base                     | Notes                                                                              |
| ------------ | ------------------------ | ---------------------------------------------------------------------------------- |
| `ideogram-4` | `leejet/ideogram-4-GGUF` | Strong prompt adherence and text rendering; uses a Qwen3-VL-8B encoder + Flux2 VAE |

Image models are defined in `images.json` (see `images.schema.json` for the schema). Each model lists the weight
`components` it needs (diffusion, unconditional diffusion, LLM text encoder, VAE), which may come from different
Hugging Face repositories and are downloaded into a single per-model directory in the `.huggingface` cache.

Manage image models with the Panther Minor CLI:

```bash
./bin/cli images list             # List supported image models
./bin/cli images download <model> # Download an image model into the .huggingface cache
./bin/cli images remove <model>   # Remove an image model from the .huggingface cache
```

## 💻 Coding Agent Presets

### OpenCode

Use `opencode.json` as the recommended [configuration](https://opencode.ai/docs/config/) for OpenCode:

```bash
cp opencode.json ~/.config/opencode/opencode.json
```

> [!IMPORTANT]
> Replace `<domain>` in `opencode.json` with your actual domain so OpenCode can connect to the API correctly.

### Pi

Use `pi/models.json` and `pi/settings.json` as the recommended [settings](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#settings) for Pi:

```bash
cp pi/*.json ~/.pi/agent/
```

> [!IMPORTANT]
> Replace `<domain>` in `models.json` with your actual domain so Pi can connect to the API correctly.
