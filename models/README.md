# Models

| Model           | Base                                | Context         | Purpose                                                                  |
|-----------------|-------------------------------------|-----------------|--------------------------------------------------------------------------|
| `panther-minor` | `Qwen3-30B-A3B-Instruct-2507-Q8_0`  | `131072` (128k) | Balanced general-purpose model for common knowledge and daily assistance |
| `panther-coder` | `Qwen3-Coder-30B-A3B-Instruct-Q8_0` | `131072` (128k) | Balanced default for daily coding work                                   |

## Usage

Supported models are stored in `config.json`. It contains name and Hugging Face repository with base file for
each model.

Then, `llama-cpp` service runs server
in [router mode](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#using-multiple-models) serving models
via `preset.ini` [configuration](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#model-presets).

### Model Management

Use the following commands in [`./bin`](./bin) to manage models in the `.huggingface` cache:

```bash
./bin/list             # List supported models
./bin/download <model> # Download model to .huggingface cache
./bin/remove <model>   # Remove model from .huggingface cache
```
