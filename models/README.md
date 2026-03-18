# Models

| Model                     | Base                                        | Q | Ctx  | Out | Purpose                                                                  |
|---------------------------|---------------------------------------------|---|------|-----|--------------------------------------------------------------------------|
| `panther-minor`           | `unsloth/Qwen3.5-35B-A3B-GGUF`              | 8 | 128k | 6k  | Balanced general-purpose model for common knowledge and daily assistance |
| `panther-minor-thinking`  | `panther-minor`                             | – | –    | –   | 🧠                                                                       |
| `panther-blazer`          | `unsloth/Qwen3.5-2B-GGUF`                   | 8 | 128k | 4k  | Light-weight general-purpose model for blazing fast inference            |
| `panther-blazer-thinking` | `panther-blazer`                            | – | –    | –   | 🧠                                                                       |
| `panther-coder`           | `unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF` | 8 | 128k | 6k  | Balanced default for daily coding work                                   |
| `panther-coder-next`      | `unsloth/Qwen3-Coder-Next-GGUF`             | 4 | 128k | 8k  | Powerful model for complex coding tasks and planning                     |

## Usage

Supported models are stored in `config.json`. It contains name and Hugging Face repository with base file for
each model.

Then, `llama-cpp` service runs server
in [router mode](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#using-multiple-models) serving models
via `preset.ini` [configuration](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#model-presets).

The bundled `llama-cpp` image is pinned to an official `ggml-org/llama.cpp` release.

### Model Management

Use the Panther Minor CLI to manage models in the `.huggingface` cache:

```bash
./bin/cli models list             # List supported models
./bin/cli models download <model> # Download model to .huggingface cache
./bin/cli models remove <model>   # Remove model from .huggingface cache
```

### OpenCode

Use `opencode.json` as the recommended [configuration](https://opencode.ai/docs/config/) for OpenCode.

```bash
cp opencode.json ~/.config/opencode/opencode.json
```

> [!IMPORTANT]
> Replace `<domain>` in `opencode.json` with your actual domain to ensure OpenCode can connect to the API
> correctly.
