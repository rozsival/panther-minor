# Models

| Model                     | Base                                        | Ctx  | Q   | Purpose                                                                  |
| ------------------------- | ------------------------------------------- | ---- | --- | ------------------------------------------------------------------------ |
| `panther-minor`           | `unsloth/Qwen3.5-35B-A3B-GGUF`              | 128k | 8   | Balanced general-purpose model for common knowledge and daily assistance |
| `panther-minor-thinking`  | `panther-minor`                             | –    | –   | 🧠                                                                       |
| `panther-blazer`          | `unsloth/Qwen3.5-2B-GGUF`                   | 128k | 8   | Light-weight general-purpose model for blazing fast inference            |
| `panther-blazer-thinking` | `panther-blazer`                            | –    | –   | 🧠                                                                       |
| `panther-coder`           | `unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF` | 128k | 8   | Balanced default for daily coding work                                   |
| `panther-coder-next`      | `unsloth/Qwen3-Coder-Next-GGUF`             | 200k | 4   | Powerful model for complex coding tasks and planning                     |

## Usage

Supported models are stored in `config.json`. It contains name and Hugging Face repository with base file for
each model.

Then, `llama-cpp` service runs server
in [router mode](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#using-multiple-models) serving models
via `preset.ini` [configuration](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#model-presets).

The bundled `llama-cpp` image is pinned to an official `ggml-org/llama.cpp` release.

### Model Management

Use the following commands in [`./bin`](./bin) to manage models in the `.huggingface` cache:

```bash
./bin/list             # List supported models
./bin/download <model> # Download model to .huggingface cache
./bin/remove <model>   # Remove model from .huggingface cache
```
