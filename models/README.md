# 🧠 Models

This directory documents the model presets supported by Panther Minor and how they are wired into the local
`llama.cpp` cluster.

## 📚 Supported models

| Model                     | Base                              | Ctx  | Out        | Purpose                                                                                                    |
| ------------------------- | --------------------------------- | ---- | ---------- | ---------------------------------------------------------------------------------------------------------- |
| `Qwen3.5-35B-A3B` 💭 👀   | `unsloth/Qwen3.5-35B-A3B-GGUF`    | 128k | 4k / 8k 💭 | Primary MoE model for complex reasoning, system architecture, and advanced problem-solving across domains  |
| `Qwen3.5-27B` 💭 👀       | `unsloth/Qwen3.5-27B-GGUF`        | 128k | 4k / 8k 💭 | Versatile dense model optimized for a wide range of tasks, from general reasoning to multimodal processing |
| `Gemma-4-26B-A4B` 💭 👀   | `unsloth/gemma-4-26B-A4B-it-GGUF` | 128k | 4k / 8k 💭 | Highly efficient MoE model balancing inference speed with deep analytical and multimodal capabilities      |
| `Gemma-4-31B` 💭 👀       | `unsloth/gemma-4-31B-it-GGUF`     | 128k | 4k / 8k 💭 | Heavyweight dense model providing maximum consistency for extensive analysis and complex workflows         |
| `Qwen3.5-2B` 💭 👀        | `unsloth/Qwen3.5-2B-GGUF`         | 128k | 2k / 8k 💭 | Lightweight dense model optimized for blazing fast inference and rapid scaffolding                         |
| `Qwen3-Embedding-0.6B` 🪶 | `Qwen/Qwen3-Embedding-0.6B-GGUF`  | 32k  | N/A        | Lightweight embedding model strictly for RAG pipelines                                                     |

### Legend

- 💭 — thinking preset
- 👀 — vision capabilities
- 🪶 — embedding-only model, no text generation

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
```

## 💻 OpenCode setup

Use `opencode.json` as the recommended [configuration](https://opencode.ai/docs/config/) for OpenCode:

```bash
cp opencode.json ~/.config/opencode/opencode.json
```

> [!IMPORTANT]
> Replace `<domain>` in `opencode.json` with your actual domain so OpenCode can connect to the API correctly.
