# Models

Local Ollama models are defined by `Modelfile` under `models/<name>/Modelfile`.

Use `MODEL=<name>` in `.env` (or `.env.example`) to select which one `make model-*` targets manage.

See the root [`README.md`](../README.md) for workflow and [`PORTS.md`](../PORTS.md) for access details.

## Available Models

| Model                 | Base                               |       `num_ctx` | `num_predict` | Purpose                                                                  |
|-----------------------|------------------------------------|----------------:|--------------:|--------------------------------------------------------------------------|
| `panther-minor`       | `qwen3:30b-a3b-thinking-2507-q8_0` | `131072` (128k) | `16384` (16k) | Balanced general-purpose model for common knowledge and daily assistance |
| `panther-coder-small` | `qwen3-coder:30b-a3b-q8_0`         |   `65536` (64k) |   `8192` (8k) | Fast responses for smaller coding tasks                                  |
| `panther-coder`       | `qwen3-coder:30b-a3b-q8_0`         | `131072` (128k) | `16384` (16k) | Balanced default for daily coding work                                   |
| `panther-coder-large` | `qwen3-coder:30b-a3b-q8_0`         | `262144` (256k) | `32768` (32k) | Heavy, highest precision for complex tasks                               |

All variants use Panther system prompts tuned for their purpose.

## Usage

```bash
make model-list
make model-create
make model-run
make model-stop
make model-remove
```

