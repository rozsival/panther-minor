# 🧠 Models

This directory documents the models supported by Panther Minor, split by modality:

- **`llm.config.json`** — large language models served by `llama.cpp`
- **`t2i.config.json`** — text-to-image models served by `stable-diffusion.cpp`

Each modality has its own catalog (`llm.config.json` + `llm.schema.json`, `t2i.config.json` + `t2i.schema.json`); how
to run both side by side is covered in [Recommended workflows](#-recommended-workflows).

## 📦 Shared model cache

Downloaded weights live in a single shared Hugging Face cache, `models/.huggingface`, mounted into both the
`llama-cpp` and `stable-diffusion-cpp` containers. Each file is stored at its repository-relative path
(`<repository>/<file>`), so a file used by more than one model is downloaded and kept **only once**, and same-named
files from different repositories (e.g. each LLM's `mmproj-F16.gguf`) never collide.

```bash
./bin/cli models llm|t2i download <model>   # Fetch only the model's missing files (-f to force re-fetch)
./bin/cli models llm|t2i remove <model>     # Delete only the files the model does not share with another
./bin/cli models prune                      # Reclaim files no config references anymore (also runs after download/remove)
```

## 📚 Large language models (`llm.config.json`)

Served by the local `llama.cpp` cluster with an OpenAI-compatible API.

### Supported models

| Model                      | Base                              | Ctx  | Purpose                                                                        |
| -------------------------- | --------------------------------- | ---- | ------------------------------------------------------------------------------ |
| `Qwen3.8-27B` 💭 👀 ⚡️️     | `unsloth/Qwen3.8-27B-GGUF`        | 262K | Primary dense model, general reasoning to multimodal                           |
| `Qwen3.6-35B-A3B` 💭 👀 ⚡️ | `unsloth/Qwen3.6-35B-A3B-GGUF`    | 262K | Versatile MoE, specialized multimodal reasoning + fast problem solving         |
| `Qwen3.5-2B` 💭 👀️ ⚡️      | `unsloth/Qwen3.5-2B-GGUF`         | 33K  | Lightweight dense, fast inference, scaffolding, image-gen chats                |
| `Qwen3-Embedding-0.6B` 🪶  | `Qwen/Qwen3-Embedding-0.6B-GGUF`  | 16K  | Lightweight embedding model, RAG pipelines only                                |
| `Qwen3.8-Flash-Next` 💭 👀 | `unsloth/Qwen3.8-Flash-Next-GGUF` | 262K | Heavyweight sparse MoE (125B total, ~6B active), long agentic/coding/reasoning |

Legend: 💭 hybrid reasoning (per-request, not per-preset) · 👀 multimodal (vision encoder enabled) · ⚡️
speculative decoding (Multi Token Prediction) · 🪶 embedding-only (no text generation)

### Configuration

Supported models are defined in `llm.config.json` (see `llm.schema.json` for the schema). At runtime, `llama-cpp`
runs in [router mode](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#using-multiple-models),
serving models through `llama-cpp/preset.ini`
[presets](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#model-presets).

- **`components`** — the weight files the model needs (main weight first, then extras like `mmproj-*` vision
  encoders or `mtp-*` draft models), each identified by Hugging Face `repository` + `file`. May span
  **different repositories**; files shared with another model are kept only once in the
  [shared cache](#-shared-model-cache).

#### Weight placement

Most models fit VRAM whole; only `n-gpu-layers` matters. `Qwen3.8-Flash-Next` needs manual placement —
`UD-Q4_K_XL` is 103.7 GiB vs. 2x 31.86 GiB VRAM.

| Setting                | Value                            | Note                                                                                              |
| ---------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------- |
| n-gram table           | 26.82 GiB `IQ4_NL`, host-side    | single `per_layer_token_embd` tensor via `ggml_get_rows`, never VRAM (Gemma 3n technique)         |
| `n-cpu-moe = 24`       | 40.9 GiB resident                | blocks 0-23 experts stay in RAM; decode streams ~0.70 GiB/token over PCIe (top-10 of 512 experts) |
| `load-mode = none`     | ~60 GiB read in                  | mmap is slower for CPU tensor overrides; box has 176 GiB free                                     |
| `tensor-split = 72,28` | —                                | balances heavy blocks, not layer count — see WARNING                                              |
| KV @ 262144 ctx        | 3.19 GiB `q8_0` (6.00 `f16`)     | only 12/48 layers cache; +0.10 GiB indexer keys, +0.11 GiB DeltaNet                               |
| Measured               | 571 t/s prefill, 18.6 t/s decode | 2222-token prompt, all 3 models resident (30.5/31.86 GiB)                                         |

> [!WARNING]
> **`tensor-split` divides by layer count, not bytes.** `llama-model.cpp` assigns layer `il` to a device via
> `il / (n_layer + 1)` vs. the normalized split — it ignores per-layer weight. `n-cpu-moe` makes the first N
> layers nearly weightless (0.08 GiB vs. 1.79 GiB with GPU-resident experts), so a balanced-looking split isn't.
> `52,48` put nineteen empty layers on GPU 0 and twenty-two heavy ones plus the output head on GPU 1: a 35.35 GiB
> allocation on a 31.86 GiB card, `cudaMalloc failed: out of memory`. Count heavy blocks, not layers.

GPU 1 stays lighter because `Qwen3-Embedding-0.6B` and `Qwen3.5-2B` pin `main-gpu = 1`, costing ~6 GiB each
while resident (the manager only arbitrates _large_ models). `UD-IQ4_XS` (87.2 GiB) trades experts down
(`IQ3_S`/`IQ4_NL` vs. `Q4_K`/`Q5_1`, ~3.9 vs. ~5.1 bits/weight) for more GPU headroom; `UD-Q5_K_XL` (147.4 GiB,
50.66 GiB n-gram table) isn't practical.

### Speculative decoding

Every ⚡️ model uses an **MTP head** (one extra dense layer sharing the base model's embeddings, run in-graph);
Unsloth ships one `Q4_0` quant per model (1.37 GB for Qwen3.8) — nothing to choose.

`Qwen3.8-Flash-Next` **has** a head (4B, one layer, 31 `mtp.*` tensors) but no ⚡️ badge: llama.cpp master
doesn't implement it (the merged `qwen4exp` port declares no `NEXTN_*` tensors; open in
[PR #27836](https://github.com/ggml-org/llama.cpp/pull/27836), which adds the draft head + a `--mtp` converter
flag), and no published GGUF carries it — every quant, Unsloth's included, parses to zero `mtp.*`/`nextn.*`
tensors (the head must live in-file; the merged reader's 32-byte alignment and exact `split.tensors.count`
checks reject grafted community exports).

Preset: `spec-type = none`, `spec-draft-n-max = 0`. Once #27836 merges and a GGUF ships the head: `spec-type =
draft-mtp`, `spec-draft-n-max = 2` (a tester on this hardware — 2x R9700, gfx1201, ROCm — measured **+17%
decode** at depth 2 with `ubatch-size 1024`, already set; depths 3-4 were **slower**; re-measure, don't trust
it). Budget: head ~2.10 GiB + ~0.27 GiB draft KV at 262144 ctx; only 1.32/1.38 GiB free with all three resident,
so `n-cpu-moe` → **26** (frees 2.93 GiB on GPU 0, +0.06 GiB/token host traffic) — worth it against +17% decode;
freed room lands on GPU 0 (blocks 24-25), so placing the head on GPU 1 needs a `tensor-split` nudge too.

#### Draft depth

`spec-draft-n-max` sets tokens proposed per round. Acceptance decays geometrically, so the optimum is where the
marginal accepted token stops paying for its draft-and-sample cycle — measure, don't assume. `llama-server`
reports `draft acceptance = <rate> (<accepted> / <generated>), mean len = <n>` per request; llama.cpp `v0.2.0`
added per-position counters:

```bash
curl -s localhost:8000/metrics | grep spec_decode_num_accepted_tokens_per_pos_total
```

Sampler-dependent: greedy accepts far more than the `temp = 1.0` these presets run — benchmark at production
sampling or the optimum lands too high.

### GPU split mode

`split-mode` spreads a model over GPUs — not free on ROCm: **`tensor`** slices every layer across every GPU
(weight stream ÷ GPU count), fastest for **dense** models (`Qwen3.8-27B`) at the cost of an all-reduce per
row-parallel projection; **`layer`** puts whole layers per GPU, no all-reduce but slower dense decode (suits
sparse MoE / uneven topologies, optionally with `tensor-split`); **`none`** is single-GPU, paired with
`main-gpu`.

`tensor` silently drops two features (load-time warning only): **backend (GPU) sampling** —
`llama_set_sampler` refuses under `SPLIT_MODE_TENSOR`, forcing CPU sampling (~0.99 MB/call at Qwen3.8's 248,320
vocab, pulling `spec-draft-n-max` down; watch for `backend sampling not supported with SPLIT_MODE_TENSOR` /
`backend offload failed for seq_id=`) — and **`llama_params_fit`**, unimplemented for tensor split, so
placement (`n-gpu-layers`, `n-cpu-moe`, `tensor-split`) is pinned by hand.

The all-reduce needs RCCL — llama.cpp's bundled "internal" implementation is CUDA-only (a HIP stub); missing
`-DGGML_HIP_RCCL=ON` (built against `/opt/rocm`'s RCCL from `rocm/dev-ubuntu-26.04`) falls back to the meta
backend and logs:

```
internal AllReduce init failed (n_devices != 2?); falling back to meta-backend butterfly
```

On `Qwen3.8-27B`, RCCL cut the forward pass **~20%** (decode ~54 → **66 tok/s** with the `spec-draft-n-max`
retune); a third of the remaining gap is CPU sampling, unrecoverable under `split-mode = tensor`.

`./bin/cli models llm bench` pins fixed prompt/seed, greedy sampling, `cache_prompt` off, `ignore_eos` on,
logging decode/prefill throughput, draft acceptance, host kernel, llama.cpp commit and image ID per entry.

### Management

```bash
./bin/cli models llm list                   # List supported LLMs
./bin/cli models llm download <model>       # Download an LLM into the cache (only missing files)
./bin/cli models llm download <model> -f    # Force re-download of the model's files
./bin/cli models llm remove <model>         # Remove an LLM's unshared files from the cache
./bin/cli models llm load <preset>          # Manually load an LLM into the llama.cpp cluster
./bin/cli models llm unload <preset>        # Manually unload an LLM from the llama.cpp cluster
./bin/cli models llm bench <preset>         # Measure throughput and append it to models/bench.log
```

`download`/`remove` take a **model name** from this file — they operate on weight files. `load`/`unload` take a
**preset name** from [`llama-cpp/preset.ini`](../llama-cpp/preset.ini), what llama-server actually serves.
Presets map 1:1 to models: thinking is a per-request switch, so changing reasoning mode never reloads weights.

### Reasoning control

Chat presets pin `reasoning` explicitly — `--reasoning auto` inherits the template default (`Qwen3.8-27B` and
`Qwen3.8-Flash-Next` think unless told not to); `Qwen3.5-2B` pins `reasoning = off` since Open WebUI drives it
as the task model for titles/tags/query rewriting, which must never think.

Per-request switches, in order of preference:

- `chat_template_kwargs: { "enable_thinking": true | false }` — works both directions regardless of preset;
  sent by the harness configs in [`harnesses/`](../harnesses/README.md).
- `chat_template_kwargs: { "reasoning_effort": … }` — `Qwen3.8-27B`/`Qwen3.8-Flash-Next` take
  `low`/`medium`/`xhigh` (`high` folds into `xhigh`; anything else raises, a 500 on Flash-Next); both presets
  pin `reasoning-effort = medium`. On `Qwen3.8-27B`, `"none"` disables thinking only while `reasoning = auto` —
  `reasoning = on` ignores it and leaks raw `<think>` tags into `content`.
- `reasoning_budget_tokens: N` — caps the trace; only `N > 0` is honoured.

Trace returns in `message.reasoning_content` (streamed as `delta.reasoning_content`). Both models default
`preserve_thinking` to true, so presets set `reasoning-preserve = off` (Flash-Next's card argues preserved
traces help agent loops — raise per request via `chat_template_kwargs`). `--reasoning-preserve` isn't a
passthrough kwarg: llama.cpp's `jinja::caps_apply_preserve_reasoning` sets `preserve_thinking`,
`clear_thinking`, `truncate_history_thinking` and `drop_thinking` together, covering every vendor spelling —
prefer it over hand-written `chat-template-kwargs`, which breaks silently if a template renames the variable.
It only drops closed-turn traces: the template keeps `<think>` blocks after the last real user message, so
tool-calling chains retain full reasoning.

In Open WebUI: type `none` into _Chat Controls → Advanced Params → reasoning_effort_, or add a Workspace Model
with `chat_template_kwargs: {"enable_thinking": false}` — unknown parameters forward to llama.cpp verbatim.

### Language coverage

`Qwen3.8-27B` is strong in English/Chinese/French/German, weaker in minor languages (Czech included) — an
upstream post-training tradeoff, not a defect: quantization (`UD-Q6_K_XL`), `q8_0` KV cache and the MTP drafter
were each measured against the live cluster and none of them contributes.

Greedy Czech output is clean (93-99.9% correct-inflection probability at unambiguous positions); what degrades
is sampled choice — at `temp = 1.0` ~22 tokens/100 diverge from greedy vs. 12 at `temp = 0.6`, and each
divergence in this heavily inflected language commits the clause to case/gender/number/aspect agreement,
producing broken concord, mistyped terminology, and script leakage.

What helps: a native-speaker system prompt with an explicit no-script-mixing instruction; lower reasoning
effort for prose (`chat_template_kwargs: { "reasoning_effort": "low" }`); lower temperature, `0.6`-`0.7`
(roughly halves divergence). Forcing Czech _thinking_ doesn't help — traces stay in English regardless. Set per
model via a Workspace Model over the same base, not globally.

---

## 🎨 Text-to-image models (`t2i.config.json`)

Served by [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)'s `sd-server`, exposing an
OpenAI-compatible image API on port `8001`.

### Supported models

| Model             | Base                           | Notes                                                                                              |
| ----------------- | ------------------------------ | -------------------------------------------------------------------------------------------------- |
| `Ideogram-4`      | `leejet/ideogram-4-GGUF`       | Strong prompt adherence and text rendering; uses a Qwen3-VL-8B encoder + Flux2 VAE                 |
| `Qwen-Image-2512` | `unsloth/Qwen-Image-2512-GGUF` | Photorealistic generation and strong text rendering (Q4_0); Qwen2.5-VL-7B encoder + Qwen-Image VAE |

> [!IMPORTANT]
> Ideogram 4 requires JSON prompts and will most likely fail to generate an image from pure text prompt. Read the
> [Prompting Guide](https://github.com/ideogram-oss/ideogram4/blob/main/docs/prompting.md#prompting-guide) for more
> information. The `ideogram4-prompt` skill (`.agents/skills/ideogram4-prompt/SKILL.md`) can generate valid JSON
> prompts from natural language descriptions, but it needs a sufficiently capable chat model to drive it — see
> [Recommended workflows](#-recommended-workflows).

### Configuration

Supported models are defined in `t2i.config.json` (see `t2i.schema.json` for the schema):

- **`components`** — the weight files a model needs (diffusion, optional unconditional diffusion, LLM text
  encoder, VAE), each identified by Hugging Face `repository` + `file`. Models only list components they use —
  Ideogram 4 has a separate unconditional diffusion model, Qwen-Image doesn't. Shared components (text encoders)
  kept only once in the [shared cache](#-shared-model-cache).
- **`args`** _(optional)_ — extra `sd-server` flags applied on load; per-model sampling defaults (e.g.
  `--flow-shift` for Qwen-Image) live here — `load` writes them to `SD_CPP_MODEL_ARGS` in `.env`, so tuning
  switches automatically with the model.

### Management

```bash
./bin/cli models t2i list                   # List supported text-to-image models
./bin/cli models t2i download <model>       # Download a model's components (only missing files)
./bin/cli models t2i download <model> -f    # Force re-download of the model's components
./bin/cli models t2i remove <model>         # Remove a model's unshared components from the cache
./bin/cli models t2i load <model>           # Serve <model> from sd-server (replaces the loaded model)
./bin/cli models t2i load -e <model>        # Same, but on a dedicated GPU (see GPU assignment)
./bin/cli models t2i unload                 # Stop sd-server (returns dedicated GPUs to the LLMs)
```

### Loading and switching

`sd-server` loads exactly **one** text-to-image model per process. `load` rewrites the active-model variables in
`.env` and recreates the single `stable-diffusion-cpp` container, replacing whatever was loaded — switching never
leaves two models in VRAM. Switching is entirely a CLI operation: `sd-server` ignores the model id in the request,
so **Open WebUI needs no changes** — leave its image model field at `default` and never touch admin image settings.

> [!NOTE]
> Because the requested model id plays no role, `IMAGE_GENERATION_MODEL` (`${SD_CPP_MODEL}` in `.env`) is just a
> label. The Images panel in Open WebUI lists only the currently-loaded model, since that is all `sd-server`
> reports at `/v1/models`.

### GPU assignment

By default, `load` only swaps the model — GPU assignment stays untouched and the LLMs keep all GPUs, the right
mode for the [everyday workflow](#everyday-chat-with-occasional-images-no-gpu-switching). For
[heavy image sessions](#heavy-image-sessions-dedicate-a-gpu), `load --exclusive` gives image generation a GPU
of its own so the two stacks never contend for VRAM:

- **`load --exclusive`** shrinks the LLMs to `LLAMA_CPP_GPUS_SHARED` (→ `ROCM_VISIBLE_DEVICES` in `.env`) and
  recreates `llama-cpp`, freeing `SD_VISIBLE_DEVICES` for `sd-server` alone.
- **`unload`** stops `sd-server`; if a previous `--exclusive` load shrank the LLMs, restores
  `LLAMA_CPP_GPUS_STANDALONE` (all GPUs) and recreates `llama-cpp` to reclaim the freed GPU.

The GPU sets live in `.env` (see `.env.example`) — edit them to match your GPU topology:

| Variable                    | Default | Meaning                                                            |
| --------------------------- | ------- | ------------------------------------------------------------------ |
| `ROCM_VISIBLE_DEVICES`      | `0,1`   | Active GPU set the LLMs run on (managed by `load -e` / `unload`)   |
| `LLAMA_CPP_GPUS_STANDALONE` | `0,1`   | GPUs the LLMs use outside exclusive mode (all GPUs)                |
| `LLAMA_CPP_GPUS_SHARED`     | `0`     | GPUs the LLMs shrink to while exclusive mode is active             |
| `SD_VISIBLE_DEVICES`        | `1`     | GPU(s) `sd-server` runs on — dedicated to it during exclusive mode |

> [!NOTE]
> `load --exclusive` and the `unload` that follows it restart `llama-cpp`, so resident LLMs reload lazily on
> the next request — the price of a clean GPU handoff. Switch modes per work session, not per image.

---

## 🧭 Recommended workflows

LLMs and image generation share the same GPUs, so running heavyweight models of both kinds at once contends for
VRAM and can OOM. Pick the workflow that matches your session:

### Everyday: chat with occasional images (no GPU switching)

The chat model's only role is **authoring the prompt** — it triggers the image tool call, hands a prompt to the
image API, and comments on the result. Pick the chat model to match the loaded image model:

| Loaded image model | Prompting                                  | Recommended chat model  | Why                                                                                                                          |
| ------------------ | ------------------------------------------ | ----------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `Qwen-Image-2512`  | Plain text                                 | `Qwen3.5-2B`            | No capacity needed to relay a plain prompt; Qwen-Image is the VRAM-heavy stack and OOMs with a heavyweight LLM               |
| `Ideogram-4`       | Structured JSON (`ideogram4-prompt` skill) | `Qwen3.8-27B` or larger | Small models can't drive the JSON-prompt skill reliably; Ideogram 4's stack is light on VRAM, so a heavyweight LLM fits fine |

1. Load a text-to-image model once: `./bin/cli models t2i load <model>`.
2. When you want images, start the chat with the model from the table above.
3. That's it — no GPU reassignment, no container restarts, and no cleanup afterwards.

`stable-diffusion.cpp` offloads weights to RAM between generations, holding VRAM only while producing an image —
idle VRAM frees itself, no manual unload needed.

> [!TIP]
> The `ideogram4-prompt` skill (`.agents/skills/ideogram4-prompt/SKILL.md`) turns natural language into valid
> Ideogram 4 JSON prompts. For Open WebUI, register it as a custom skill/prompt in the admin settings so image
> chats can use it directly — just drive it with a sufficiently capable chat model.

### Heavy image sessions: dedicate a GPU

When generating lots of images, or for a pairing the shared GPUs cannot fit — most notably **Qwen-Image next to a
heavyweight LLM** — give image generation a GPU of its own:

```bash
./bin/cli models t2i load --exclusive <model>   # LLMs shrink onto their own GPU(s), sd-server gets a dedicated one
./bin/cli models t2i unload                     # Done: sd-server stops, all GPUs return to the LLMs
```

See [GPU assignment](#gpu-assignment) for how the split works and how to adapt it to your GPU topology.

> [!WARNING]
> OOM errors are most likely when the **Qwen-Image** stack runs alongside a larger LLM (27B+) on the shared GPUs.
> Ideogram 4's stack is much lighter and tolerates a heavyweight neighbor. When in doubt — or when generating while
> an LLM is under heavy load — use `--exclusive`.
