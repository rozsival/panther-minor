# 🧠 Models

This directory documents the models supported by Panther Minor, split by modality:

- **`llm.config.json`** — large language models served by `llama.cpp`
- **`t2i.config.json`** — text-to-image models served by `stable-diffusion.cpp`

Each modality has its own catalog (`llm.config.json` + `llm.schema.json`, `t2i.config.json` + `t2i.schema.json`); how to run both side by side is covered in
[Recommended workflows](#-recommended-workflows).

## 📦 Shared model cache

Downloaded weights live in a single shared Hugging Face cache, `models/.huggingface`, mounted into both the
`llama-cpp` and `stable-diffusion-cpp` containers. Each file is stored at its repository-relative path
(`<repository>/<file>`), so:

- a file used by more than one model is downloaded and kept **only once**,
- same-named files from different repositories (such as each LLM's `mmproj-F16.gguf`) never collide.

The cache is managed entirely by the CLI:

```bash
./bin/cli models llm|t2i download <model>   # Fetch only the model's missing files (-f to force re-fetch)
./bin/cli models llm|t2i remove <model>     # Delete only the files the model does not share with another
./bin/cli models prune                      # Reclaim files no config references anymore (also runs after download/remove)
```

## 📚 Large language models (`llm.config.json`)

Served by the local `llama.cpp` cluster with an OpenAI-compatible API.

### Supported models

| Model                          | Base                                  | Ctx  | Purpose                                                                                                     |
| ------------------------------ | ------------------------------------- | ---- | ----------------------------------------------------------------------------------------------------------- |
| `Qwen3.8-27B` 💭 👀 ⚡️️         | `unsloth/Qwen3.8-27B-GGUF`            | 262K | Primary dense model optimized for a wide range of tasks, from general reasoning to multimodal processing    |
| `Qwen3.6-35B-A3B` 💭 👀 ⚡️     | `unsloth/Qwen3.6-35B-A3B-GGUF`        | 262K | Versatile MoE model for highly specialized tasks, including multimodal reasoning and fast problem solving   |
| `Qwen3.5-2B` 💭 👀️ ⚡️          | `unsloth/Qwen3.5-2B-GGUF`             | 33K  | Lightweight dense model optimized for blazing fast inference, rapid scaffolding, and image-generation chats |
| `Qwen3-Embedding-0.6B` 🪶      | `Qwen/Qwen3-Embedding-0.6B-GGUF`      | 16K  | Lightweight embedding model strictly for RAG pipelines                                                      |
| `DeepSeek-V4-Flash-0731` 💭 ⚡️ | `unsloth/DeepSeek-V4-Flash-0731-GGUF` | 262K | Heavyweight sparse MoE (284B total, ~10B active) for long-running agentic, coding, and deep reasoning tasks |

Legend:

- 💭 — hybrid reasoning (thinking is switched per request, not per preset)
- 👀 — multimodal capabilities (vision encoder enabled)
- ⚡️ — speculative decoding enabled (Multi Token Prediction, or a DSpark draft model)
- 🪶 — embedding-only model (no text generation)

### Configuration

Supported models are defined in `llm.config.json` (see `llm.schema.json` for the schema). At runtime, the
`llama-cpp` service runs in
[router mode](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#using-multiple-models) and serves models
through `llama-cpp/preset.ini`
[presets](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#model-presets).

- **`components`** — the weight files the model needs (main weight first, then extras such as `mmproj-*` vision
  encoders or `mtp-*` draft models), each identified by its Hugging Face `repository` and `file`. Components may come
  from **different repositories**, and files shared with another model are kept only once in the
  [shared cache](#-shared-model-cache).

### Speculative decoding

Both shapes marked ⚡️ above accelerate decoding, but they are different mechanisms, which matters when
picking component files:

- **MTP head** (`Qwen3.8-27B`, `Qwen3.6-35B-A3B`, `Qwen3.5-2B`) — a single extra layer that shares the base
  model's embeddings and runs inside the same graph. Dense, so quantization has real headroom, and Unsloth
  ships one precision per model (`Q4_0`, 1.37 GB for Qwen3.8). Nothing to choose.
- **DSpark drafter** (`DeepSeek-V4-Flash-0731`) — a standalone 3-block MoE sidecar
  (`dflash.block_count = 3`), so `spec-draft-ngl = 3` already holds **all** of it on GPU and `99` is the
  same thing. It ships no token embeddings or output head and borrows the target's, so it must span the
  same devices as the target — never pin it with `--spec-draft-device`. `spec-draft-n-max` is clamped to
  the checkpoint's `dspark_block_size`, which is `5`.

The DeepSeek drafter's `Q8_0` filename is misleading: only 4.4% of the file is `Q8_0`.

| Tensors | Type    | Size     | Share | What                                                                    |
| ------- | ------- | -------- | ----- | ----------------------------------------------------------------------- |
| 9       | `MXFP4` | 10.27 GB | 94.3% | 256 routed experts — native in DeepSeek's checkpoint, never requantized |
| 25      | `Q8_0`  | 0.47 GB  | 4.4%  | FP8 `E4M3` projections                                                  |
| 6       | `BF16`  | 0.14 GB  | 1.3%  | Markov / confidence heads                                               |
| 41      | `F32`   | 0.01 GB  | 0.1%  | Norms                                                                   |

It is therefore **already a 4-bit drafter**, and there is no smaller variant to switch to. The repo's only
alternative (`dspark/…-BF16.gguf`, 11.31 GB) differs solely in those 25 projections and measures
identically. A hand-built 4-bit conversion would recover at most ~0.3 GB — under a tenth of the ~3 GB that
one `n-cpu-moe` step costs — while quantizing the heads that choose the drafts would cost acceptance rate.

#### Draft depth

`spec-draft-n-max` sets how many tokens the drafter proposes per round. Acceptance decays geometrically,
so the optimum is where the marginal accepted token stops paying for its draft-and-sample cycle — not the
largest value the checkpoint allows. Measure it, don't assume: `llama-server` reports
`draft acceptance = <rate> (<accepted> / <generated>), mean len = <n>` per request, and llama.cpp `v0.2.0`
added per-position counters that show exactly where acceptance falls off:

```bash
curl -s localhost:8000/metrics | grep spec_decode_num_accepted_tokens_per_pos_total
```

Note that acceptance is sampler-dependent: greedy decoding accepts far more than the `temp = 1.0` these
presets run at, so benchmark at production sampling or the optimum lands too high.

### GPU split mode

`split-mode` decides how a model is spread over the GPUs, and the choice is not free on ROCm:

- **`tensor`** — every GPU holds a slice of every layer, so the weight stream per GPU is divided by the
  GPU count. For **dense** models, where decode is bandwidth-bound on weights, this is the fastest option
  and is what `Qwen3.8-27B` uses. The cost is an all-reduce after every row-parallel projection.
- **`layer`** — whole layers per GPU. No all-reduce, but a single request streams the full weights through
  one GPU at a time, so dense decode is slower. Suits sparse MoE models and uneven topologies, optionally
  with `tensor-split`.
- **`none`** — single GPU, paired with `main-gpu`.

Two llama.cpp features are unavailable under `tensor`, both silent apart from a load-time warning:

- **Backend (GPU) sampling.** `llama_set_sampler` refuses under `SPLIT_MODE_TENSOR`, so sampling runs on
  the CPU — every draft and verify position ships a full logit vector over PCIe. With Qwen3.8's 248,320
  vocab that is ~0.99 MB per sample call, which raises the per-draft-token cost well above the drafter's
  own weight cost and pulls the best `spec-draft-n-max` down. Look for
  `backend sampling not supported with SPLIT_MODE_TENSOR` and `backend offload failed for seq_id=`.
- **`llama_params_fit`.** Not implemented for tensor split, so placement must be pinned by hand
  (`n-gpu-layers`, `n-cpu-moe`, `tensor-split`) rather than fitted automatically.

The all-reduce itself needs a collectives library. llama.cpp's bundled "internal" implementation is
**CUDA-only** — on HIP it is a stub that always fails — so without RCCL every reduction falls back to the
meta backend's generic path. This is why the image builds with `-DGGML_HIP_RCCL=ON`, using the RCCL headers,
library, and CMake config that the `rocm/dev-ubuntu-26.04` base image ships under `/opt/rocm`. A build
missing it logs:

```
internal AllReduce init failed (n_devices != 2?); falling back to meta-backend butterfly
```

The `n_devices` hint is misleading on ROCm — the device count is irrelevant when the implementation is
compiled out. Any `split-mode = tensor` preset depends on that flag to perform: on `Qwen3.8-27B` enabling
it cut the target forward pass by **~20%**, taking decode from ~54 to **66 tok/s** together with the
`spec-draft-n-max` retune. Roughly a third of what remains is the CPU sampling above, which no
configuration can recover while `split-mode = tensor` stands.

Numbers like these are only meaningful against a recorded baseline, so `./bin/cli models llm bench`
pins every variable that would otherwise drift - fixed prompt and seed, greedy sampling, `cache_prompt`
off so prefill is measured rather than replayed, and `ignore_eos` on so exactly `--tokens` are predicted.
Each entry records decode and prefill throughput, speculative draft acceptance, and the host kernel,
llama.cpp commit and image ID, so a later regression identifies which of those four moved.

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

`download` and `remove` take a **model name** from this file — they operate on weight files. `load` and
`unload` take a **preset name** from [`llama-cpp/preset.ini`](../llama-cpp/preset.ini), which is what
llama-server actually serves. Presets map 1:1 to models: thinking is a per-request switch, so changing
reasoning mode never reloads weights.

### Reasoning control

Chat presets pin `reasoning` explicitly instead of relying on the template default, because the two chat
templates disagree about what that default is: `Qwen3.8-27B` thinks unless told not to, while the Unsloth
`DeepSeek-V4-Flash-0731` template sets `thinking = false`. `--reasoning auto` sends no `enable_thinking`
kwarg at all, so it inherits whatever the template chose — which is why DeepSeek pins `reasoning = on` to
get the Think High behaviour its model card documents. `Qwen3.5-2B` pins `reasoning = off` instead, because
Open WebUI drives it as the task model for titles, tags and query rewriting, which must never think.

Per-request switches, in order of preference:

- `chat_template_kwargs: { "enable_thinking": true | false }` — works in both directions regardless of what
  the preset says. This is what the harness configs in [`harnesses/`](../harnesses/README.md) send.
- `chat_template_kwargs: { "reasoning_effort": … }` — sets how deep the model thinks. Both the vocabulary
  and the failure mode are per-model:
  - `Qwen3.8-27B` takes `low`, `medium`, `xhigh`. `high` folds into `xhigh`, and anything else (`minimal`,
    `max`) makes the template raise instead of answering. Its own default is `xhigh`, so the preset pins
    `reasoning-effort = medium` and lets clients ask for more. `"none"` disables thinking outright, but
    only while the preset leaves `reasoning = auto` — a preset pinning `reasoning = on` ignores it and
    leaks raw `<think>` tags into `content`.
  - `DeepSeek-V4-Flash-0731` takes `high` and `max`, each prepending an effort preamble to the system
    prompt. Every other value — including `"none"` — is silently ignored and leaves plain thinking, so the
    model has three real modes: non-think, Think High, Think Max. Effort is gated behind thinking, so it
    does nothing while `enable_thinking` is false.
- `reasoning_budget_tokens: N` — caps the trace at `N` tokens. Only `N > 0` is honoured; `0` is ignored.

The trace comes back in `message.reasoning_content`, streamed as `delta.reasoning_content`.

`Qwen3.8-27B` also replays every historical `<think>` block into the prompt unless told not to — its
template defaults `preserve_thinking` to true — so the preset sets `reasoning-preserve = off`. Note that
`--reasoning-preserve` does not pass a kwarg of that name through: llama.cpp intercepts it and applies a
dialect-normalizing layer (`jinja::caps_apply_preserve_reasoning`) that sets `preserve_thinking`,
`clear_thinking`, `truncate_history_thinking` and `drop_thinking` together, so the one flag covers every
vendor's spelling. Prefer it over hand-written `chat-template-kwargs`, which pins a single spelling and
silently stops working if a future template renames the variable.

Turning preservation off does not touch reasoning inside the current turn: the template keeps the
`<think>` block of every assistant message after the last real user message, so a multi-step tool-calling
chain retains its full reasoning. Only traces from turns that closed before the latest user message drop.

`DeepSeek-V4-Flash-0731` needs no such flag, and would ignore it: its template reads none of those four
variables. Its retention rule is hardcoded — `keep_reasoning = tools_present or (index > last_user_index)`
— so as soon as a request carries tools, **every** historical `<think>` block is replayed, with no way to
turn it off from the preset. Budget context accordingly on long agentic runs; the model card also asks for
at least 384K context for Think Max, above the 262144 the preset sets.

In Open WebUI, either type `none` into _Chat Controls → Advanced Params → reasoning_effort_, or add a
Workspace Model over the same base model with the custom parameter `chat_template_kwargs` set to
`{"enable_thinking": false}` — unknown parameters are forwarded to llama.cpp verbatim.

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
> Ideogram 4 requires JSON prompts and will most likely fail to generate an image from pure text prompt.
> Read the [Prompting Guide](https://github.com/ideogram-oss/ideogram4/blob/main/docs/prompting.md#prompting-guide) for more information.
> The `ideogram4-prompt` skill (`.agents/skills/ideogram4-prompt/SKILL.md`) can generate valid JSON prompts from natural language descriptions,
> but it needs a sufficiently capable chat model to drive it — see [Recommended workflows](#-recommended-workflows).

### Configuration

Supported models are defined in `t2i.config.json` (see `t2i.schema.json` for the schema):

- **`components`** — the weight files a model needs (diffusion, optional unconditional diffusion, LLM text encoder,
  VAE), each identified by its Hugging Face `repository` and `file`. Models only list the components they use —
  Ideogram 4 has a separate unconditional diffusion model, Qwen-Image does not. Shared components (such as text
  encoders) are kept only once in the [shared cache](#-shared-model-cache).
- **`args`** _(optional)_ — extra `sd-server` flags applied when the model is loaded. This is where per-model sampling
  defaults live (e.g. `--flow-shift` for Qwen-Image); `load` writes them to `SD_CPP_MODEL_ARGS` in `.env`, so the
  tuning switches automatically with the model.

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

`sd-server` loads exactly **one** text-to-image model per process, so only one is ever resident. `load` rewrites the
active-model variables in `.env` and recreates the single `stable-diffusion-cpp` container, replacing whatever was
loaded before — switching never leaves two models in VRAM.

Switching is entirely a CLI operation. `sd-server` serves whatever model it currently has loaded and ignores the model
id in the request, so **Open WebUI needs no changes**: leave its image model field at `default`. You never touch the
admin image settings when switching.

> [!NOTE]
> Because the requested model id plays no role, `IMAGE_GENERATION_MODEL` (`${SD_CPP_MODEL}` in `.env`) is just a label.
> The Images panel in Open WebUI lists only the currently-loaded model, since that is all `sd-server` reports at
> `/v1/models`.

### GPU assignment

By default, `load` only swaps the model — the GPU assignment is left untouched and the LLMs keep all GPUs. This is the
right mode for the [everyday workflow](#everyday-chat-with-occasional-images-no-gpu-switching).

For [heavy image sessions](#heavy-image-sessions-dedicate-a-gpu), `load --exclusive` hands image generation a GPU of
its own so the two stacks never contend for the same VRAM:

- **`load --exclusive`** shrinks the LLMs to `LLAMA_CPP_GPUS_SHARED` (writing it to `ROCM_VISIBLE_DEVICES` in `.env`)
  and recreates `llama-cpp`, freeing `SD_VISIBLE_DEVICES` for `sd-server` alone.
- **`unload`** stops `sd-server` and — only if a previous `--exclusive` load shrank the LLMs — restores them to
  `LLAMA_CPP_GPUS_STANDALONE` (all GPUs) and recreates `llama-cpp` so it reclaims the freed GPU.

The GPU sets live in `.env` (see `.env.example`) — edit them to match your GPU topology:

| Variable                    | Default | Meaning                                                            |
| --------------------------- | ------- | ------------------------------------------------------------------ |
| `ROCM_VISIBLE_DEVICES`      | `0,1`   | Active GPU set the LLMs run on (managed by `load -e` / `unload`)   |
| `LLAMA_CPP_GPUS_STANDALONE` | `0,1`   | GPUs the LLMs use outside exclusive mode (all GPUs)                |
| `LLAMA_CPP_GPUS_SHARED`     | `0`     | GPUs the LLMs shrink to while exclusive mode is active             |
| `SD_VISIBLE_DEVICES`        | `1`     | GPU(s) `sd-server` runs on — dedicated to it during exclusive mode |

> [!NOTE]
> `load --exclusive` and the `unload` that follows it restart `llama-cpp`, so any resident LLMs reload lazily on the
> next request. This is the price of a clean GPU handoff — switch modes per work session, not per image.

---

## 🧭 Recommended workflows

LLMs and image generation share the same GPUs, so running heavyweight models of both kinds at once contends for VRAM
and can OOM. Pick the workflow that matches your session:

### Everyday: chat with occasional images (no GPU switching)

The chat model plays a small role in the mechanics of image generation — it triggers the image tool call, hands a
prompt to the image API, and comments on the result. What it must be able to do is **author the prompt**, and that is
where the two text-to-image models differ, so pick the chat model to match the loaded image model:

| Loaded image model | Prompting                                  | Recommended chat model  | Why                                                                                                                                                                |
| ------------------ | ------------------------------------------ | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Qwen-Image-2512`  | Plain text                                 | `Qwen3.5-2B`            | Relaying a text prompt needs no capacity — and staying lightweight matters, because Qwen-Image is the VRAM-heavy stack and OOMs when paired with a heavyweight LLM |
| `Ideogram-4`       | Structured JSON (`ideogram4-prompt` skill) | `Qwen3.8-27B` or larger | Small models lack the capacity to drive the JSON-prompt skill reliably — and Ideogram 4's stack is light on VRAM, so a heavyweight LLM coexists with it just fine  |

1. Load a text-to-image model once: `./bin/cli models t2i load <model>`.
2. When you want images, start the chat with the model from the table above.
3. That's it — no GPU reassignment, no container restarts, and no cleanup afterwards.

`stable-diffusion.cpp` offloads its weights to RAM between generations, so it only holds VRAM while actually producing
an image — idle VRAM frees itself, no manual unload needed.

> [!TIP]
> The `ideogram4-prompt` skill (`.agents/skills/ideogram4-prompt/SKILL.md`) turns natural language into valid Ideogram 4
> JSON prompts. For Open WebUI, register it as a custom skill/prompt in the admin settings so image chats can use it
> directly — just drive it with a sufficiently capable chat model.

### Heavy image sessions: dedicate a GPU

When you generate lots of images, or need a pairing the shared GPUs cannot fit — most notably **Qwen-Image next to a
heavyweight LLM** — give image generation a GPU of its own:

```bash
./bin/cli models t2i load --exclusive <model>   # LLMs shrink onto their own GPU(s), sd-server gets a dedicated one
./bin/cli models t2i unload                     # Done: sd-server stops, all GPUs return to the LLMs
```

See [GPU assignment](#gpu-assignment) for how the split works and how to adapt it to your GPU topology.

> [!WARNING]
> OOM errors are most likely when the **Qwen-Image** stack runs alongside a larger LLM (27B+) on the shared GPUs.
> Ideogram 4's stack is much lighter and tolerates a heavyweight neighbor. When in doubt — or when generating while an
> LLM is under heavy load — use `--exclusive`.
