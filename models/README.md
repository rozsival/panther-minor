# Models

Custom Ollama models managed via local `Modefile` entries. Each model lives in its own directory named after the model.

See [`Modelfile` reference](https://docs.ollama.com/modelfile) for syntax details.

## Available Models

### `panther-coder`

> Elite senior software engineer persona, optimized for precise and deterministic code generation.

| Parameter        | Value                      |
|------------------|----------------------------|
| Base model       | `qwen3-coder:30b-a3b-q8_0` |
| `temperature`    | `0.2`                      |
| `repeat_penalty` | `1.1`                      |
| `top_p`          | `0.9`                      |
| `num_ctx`        | `262144` (256k tokens)     |

## Usage

```bash
# Build/update a model from its Modelfile
make model-create

# Unload from memory
make model-stop

# Delete from Ollama
make model-remove
```

All targets use the `MODEL` value from `.env`.

