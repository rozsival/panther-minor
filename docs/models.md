# 🧠 Models

> Panther Minor serves two modalities, each with its own catalog: large language models via `llama.cpp` and
> text-to-image models via `stable-diffusion.cpp`. Weights for both live in one shared, deduplicated Hugging Face
> cache managed by the CLI.

**Related:** [LLM serving](llm.md) · [Image generation](image-generation.md) · [GPU power & VRAM](gpu-management.md)
· [CLI reference](cli.md#models)

---

## 🗂️ Catalog files

| Modality      | Catalog                  | Schema                   | Served by                              |
| ------------- | ------------------------ | ------------------------ | -------------------------------------- |
| LLM           | `models/llm.config.json` | `models/llm.schema.json` | `llama-cpp` via `llama-cpp/preset.ini` |
| Text-to-image | `models/t2i.config.json` | `models/t2i.schema.json` | `stable-diffusion-cpp` (`sd-server`)   |

Each model lists its **`components`** — the weight files it needs, each by Hugging Face `repository` + `file`,
possibly across repositories. Both modalities can run [side by side](image-generation.md#-recommended-workflows).

## 📚 Large language models

| Model                         | Base                              | Ctx  | Purpose                                                                        |
| ----------------------------- | --------------------------------- | ---- | ------------------------------------------------------------------------------ |
| `Qwen3.8-27B` 💭 👀 ⚡️        | `unsloth/Qwen3.8-27B-GGUF`        | 262K | Primary dense model, general reasoning to multimodal                           |
| `Qwen3.6-35B-A3B` 💭 👀 ⚡️    | `unsloth/Qwen3.6-35B-A3B-GGUF`    | 262K | Versatile MoE, specialized multimodal reasoning + fast problem solving         |
| `Qwen3.5-2B` 💭 👀️ ⚡️         | `unsloth/Qwen3.5-2B-GGUF`         | 33K  | Lightweight dense, fast inference, scaffolding, image-gen chats                |
| `Qwen3-Embedding-0.6B` 🪶     | `Qwen/Qwen3-Embedding-0.6B-GGUF`  | 16K  | Lightweight embedding model, RAG pipelines only                                |
| `Qwen3.8-Flash-Next` 💭 👀 ⚡️ | `unsloth/Qwen3.8-Flash-Next-GGUF` | 262K | Heavyweight sparse MoE (125B total, ~6B active), long agentic/coding/reasoning |

**Legend:** 💭 hybrid reasoning (per-request, not per-preset) · 👀 multimodal (vision encoder enabled) · ⚡️
speculative decoding (Multi Token Prediction) · 🪶 embedding-only (no text generation)

### Open WebUI roles

| Role           | Model                  | Set by (`docker-compose.yml`)       |
| -------------- | ---------------------- | ----------------------------------- |
| Default chat   | `Qwen3.8-27B`          | `DEFAULT_MODELS`                    |
| Task model     | `Qwen3.5-2B`           | `TASK_MODEL`, `TASK_MODEL_EXTERNAL` |
| RAG embeddings | `Qwen3-Embedding-0.6B` | `RAG_EMBEDDING_MODEL`               |

Serving, tuning and reasoning control: [LLM serving](llm.md).

## 🎨 Text-to-image models

| Model            | Base                          | Notes                                                                                                             |
| ---------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `Ideogram-4`     | `leejet/ideogram-4-GGUF`      | Default. Strong prompt adherence and text rendering; Qwen3-VL-8B encoder + Flux2 VAE; **requires JSON prompts**   |
| `Qwen-Image-2.1` | `unsloth/Qwen-Image-2.1-GGUF` | 7B photorealistic generation, native transparency (RGBA) and text rendering (Q8_0); Qwen3-VL-8B encoder + own VAE |

Switching, prompting and GPU sharing: [Image generation](image-generation.md).

## 📦 Shared model cache

Weights live in one shared Hugging Face cache, `models/.huggingface`, bind-mounted into both inference containers.
Each file is stored at its repository-relative path (`<repository>/<file>`), so:

- a file used by more than one model is kept **only once** (both image models share the Qwen3-VL-8B encoder);
- same-named files from different repositories never collide.

## 📥 Managing weights

```bash
./bin/panther-minor models llm list                     # Supported model names
./bin/panther-minor models llm download <model> [-f]    # Fetch missing files (-f forces re-download)
./bin/panther-minor models llm remove <model>           # Delete files no other model uses
./bin/panther-minor models t2i list|download|remove ... # Same for text-to-image models
./bin/panther-minor models prune                        # Reclaim files no catalog references anymore
```

`download` and `remove` take a **model name** from the catalog. Downloads read `HF_TOKEN` from `.env` or the shell
environment when set (`HF_TOKEN=<token> ./bin/panther-minor models llm download <model>`).

> [!NOTE]
> Downloading does not serve a model. LLMs load on demand or via `models llm load <preset>`
> ([LLM serving](llm.md#-management)); the image model is selected with `models t2i load <model>`
> ([Image generation](image-generation.md#-management)).

## ➕ Adding a model

New LLMs touch several files at once — `models/llm.config.json`, `llama-cpp/preset.ini`, `llama-cpp/models.js` (large
models) and the [harness presets](harnesses.md). The `add-model` agent skill (`.agents/skills/add-model/SKILL.md`)
walks through every field and applies the edits consistently. Update the catalog table above in the same change.

---

## ❓ FAQ

### What is the difference between a model name and a preset name?

A **model name** identifies weights in `*.config.json` and is used by `download`/`remove`. A **preset name** is a
section in `llama-cpp/preset.ini` — what `llama-server` actually serves — and is used by `load`/`unload`/`bench`.
Presets map 1:1 to models.

### Will removing a model break another one that shares files?

No. `remove` deletes only files no other configured model references.

### Is a Hugging Face token required?

No, but it avoids rate limits on large downloads. Put it in `.env` as `HF_TOKEN` or pass it inline.

### Where did my disk space go after changing the catalog?

Files dropped from every catalog stay in the cache until you run `./bin/panther-minor models prune`.

### Why are there no separate "thinking" models?

Reasoning is switched per request, so one preset serves both modes without reloading weights. See
[Reasoning control](llm.md#-reasoning-control).
