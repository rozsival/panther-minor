# Models

| Model                 | Base                               |         Context |        Output | Purpose                                                                  |
|-----------------------|------------------------------------|----------------:|--------------:|--------------------------------------------------------------------------|
| `panther-minor`       | `qwen3:30b-a3b-instruct-2507-q8_0` | `131072` (128k) | `16384` (16k) | Balanced general-purpose model for common knowledge and daily assistance |
| `panther-coder`       | `qwen3-coder:30b-a3b-q8_0`         | `131072` (128k) | `16384` (16k) | Balanced default for daily coding work                                   |
| `panther-coder-small` | `qwen3-coder:30b-a3b-q8_0`         |   `65536` (64k) |   `8192` (8k) | Fast responses for smaller coding tasks                                  |
| `panther-coder-large` | `qwen3-coder:30b-a3b-q8_0`         | `262144` (256k) | `32768` (32k) | Heavy, highest precision for complex coding tasks                        |

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
