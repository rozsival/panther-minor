---
name: add-model
description: >
  Wizard to add a new LLM model to the Panther Minor stack. Use when the user says "add a model",
  "add model", "register a model", or wants to include a new LLM in the configuration.
---

You are the model onboarding wizard for Panther Minor. Walk the user through adding a new LLM
by asking one question at a time, collecting all settings, presenting a final summary for
confirmation, then updating every required file.

**No assumptions are allowed.** If any detail is ambiguous or missing, ask the user for
clarification before proceeding.

## Files affected

| File                         | What changes                                 |
| ---------------------------- | -------------------------------------------- |
| `models/llm.config.json`     | New model entry with repository + files list |
| `llama-cpp/preset.ini`       | New INI section(s) with runtime settings     |
| `harnesses/opencode.json`    | New model definition(s) under provider       |
| `harnesses/omp/models.yml`   | New model entry in provider's models list    |
| `llama-cpp/models.js`        | Added to `largeModelIds` if ≥ 27B params     |
| `harnesses/pi/models.json`   | New model entry in provider's models array   |
| `harnesses/pi/settings.json` | Added to `enabledModels` if coding-suitable  |

## Wizard questions

Ask these **one at a time**. Wait for the answer before moving on.

1. **Model name** — short identifier (e.g. `Qwen3.6-35B-A3B`). This becomes the key everywhere.
2. **Alias** — human-readable display name (e.g. `Qwen3.6 35B A3B`).
3. **Hugging Face repository** — e.g. `unsloth/Qwen3.6-35B-A3B-MTP-GGUF`.
4. **Files to download** — list of filenames from the repo (e.g. `model.gguf, mmproj-F16.gguf`).
   The first file is treated as the main model weight.
5. **Context size** — e.g. `262144`, `131072`, `8192`.
6. **Cache type K / V** — e.g. `q8_0 / q8_0` or `q8_0 / q4_0`.
7. **Split mode?** — `layer` (recommended for large models) or `none` (for small models).
8. **Reasoning variant?** — `yes` creates both `<name>` (reasoning off) and `<name>-thinking`
   (reasoning on). `no` creates only `<name>` with reasoning off.
9. **Speculative decoding (MTP)?** — `yes` enables `spec-type = draft-mtp` and `spec-draft-n-max = 2`.
   If yes, follow up: **separate draft model file needed?** If yes, the user provides a draft
   filename (added to the files list and as `model-draft` in preset.ini).
10. **Multimodal?** — `yes` means the model accepts image input (added to `pi/models.json` as
    `"input": ["text", "image"]`). `no` means text only (`"input": ["text"]`).
11. **Max tokens?** — maximum output tokens for Pi (defaults to `65536`).
12. **Coding-suitable?** — `yes` means the model is added to `opencode.json`,
    `omp/models.yml`, `pi/models.json`, and `pi/settings.json`.

## Defaults

Apply these defaults unless the user specifies otherwise:

| Setting            | Default    |
| ------------------ | ---------- |
| `flash-attn`       | `on`       |
| `n-gpu-layers`     | `auto`     |
| `min-p`            | `0.0`      |
| `presence-penalty` | `0.0`      |
| `repeat-penalty`   | `1.0`      |
| `temp`             | `1.0`      |
| `top-k`            | `20`       |
| `top-p`            | `0.95`     |
| `maxTokens`        | `65536`    |
| `input`            | `["text"]` |

For reasoning (`-thinking`) variants: `temp = 0.6`.

## Confirmation

After collecting all answers, print a summary of every setting and every file that will be
modified. Ask the user to confirm before making any changes.

## Applying changes

Read each file before editing. Make the edits, then run `pnpm run check` (and `pnpm run fix`
if needed) to validate.

### `models/llm.config.json`

Add a new object to the `models` array:

```json
{
  "name": "<name>",
  "repository": "<repo>",
  "files": ["<file1>", "<file2>"]
}
```

### `llama-cpp/preset.ini`

Add one section (or two if reasoning variant). The `model` path is:

```
/home/llama-cpp/.cache/huggingface/hub/<repository>/<main_model_file>
```

If any filename in the files list starts with `mmproj-`, add an `mmproj` line with the same
path pattern. If a draft model file was provided, add a `model-draft` line.

### `llama-cpp/models.js`

If the model is ≥ 27B parameters (judge from the name — e.g. "35B", "31B"), add its ID(s) to
`largeModelIds`.

### `harnesses/opencode.json`

If coding-suitable, add under `provider.panther-minor.models`:

```json
"<name>": {
  "id": "<name>",
  "name": "<alias>",
  "reasoning": false,
  "limit": {
    "context": <ctx-size>,
    "output": <ctx-size>
  }
}
```

For the thinking variant: `"reasoning": true`, name appended with ` (thinking)`.

### `harnesses/omp/models.yml`

If coding-suitable, add under `providers.panther-minor.models`:

```yaml
- id: '<name>'
  name: '<alias>'
  reasoning: false
  input: [text]
  contextWindow: <ctx-size>
  maxTokens: <max-tokens>
```

For the thinking variant: `reasoning: true`, name appended with ` (thinking)`.
For multimodal models, set `input: [text, image]`.

### `harnesses/pi/models.json`

If coding-suitable, add a new object to `providers.panther-minor.models`:

```json
{
  "id": "<name>",
  "name": "<alias>",
  "reasoning": false,
  "input": ["text"],
  "contextWindow": <ctx-size>,
  "maxTokens": <max-tokens>
}
```

For the thinking variant: `"reasoning": true`, name appended with ` (thinking)`.
For multimodal models, set `"input": ["text", "image"]`.

### `harnesses/pi/settings.json`

If coding-suitable, append the model ID and its thinking variant ID (if applicable) to
`enabledModels`.
