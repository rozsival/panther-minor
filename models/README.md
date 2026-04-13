# 🧠 Models

This directory documents the model presets supported by Panther Minor and how they are wired into the local
`llama.cpp` cluster.

## 📚 Supported models

| Model                     | Base                             | Q   | Ctx  | Out        | Purpose                                                   |
| ------------------------- | -------------------------------- | --- | ---- | ---------- | --------------------------------------------------------- |
| `Qwen3.5-35B-A3B` 🧠 👀   | `unsloth/Qwen3.5-35B-A3B-GGUF`   | 8   | 128k | 4k / 6k 🧠 | Balanced, versatile model for daily use                   |
| `Qwen3.5-2B` 🧠 👀        | `unsloth/Qwen3.5-2B-GGUF`        | 8   | 128k | 2k / 4k 🧠 | Lightweight general-purpose model for very fast inference |
| `Qwen3-Embedding-0.6B` 🪶 | `Qwen/Qwen3-Embedding-0.6B-GGUF` | 8   | 32k  | -          | Lightweight embedding model for RAG                       |

### Legend

- 🧠 — thinking preset
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
