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

| Model                      | Base                              | Ctx  | Purpose                                                                                                     |
| -------------------------- | --------------------------------- | ---- | ----------------------------------------------------------------------------------------------------------- |
| `Qwen3.8-27B` 💭 👀 ⚡️️     | `unsloth/Qwen3.8-27B-GGUF`        | 262K | Primary dense model optimized for a wide range of tasks, from general reasoning to multimodal processing    |
| `Qwen3.6-35B-A3B` 💭 👀 ⚡️ | `unsloth/Qwen3.6-35B-A3B-GGUF`    | 262K | Versatile MoE model for highly specialized tasks, including multimodal reasoning and fast problem solving   |
| `Qwen3.5-2B` 💭 👀️ ⚡️      | `unsloth/Qwen3.5-2B-GGUF`         | 33K  | Lightweight dense model optimized for blazing fast inference, rapid scaffolding, and image-generation chats |
| `Qwen3-Embedding-0.6B` 🪶  | `Qwen/Qwen3-Embedding-0.6B-GGUF`  | 16K  | Lightweight embedding model strictly for RAG pipelines                                                      |
| `Qwen3.8-Flash-Next` 💭 👀 | `unsloth/Qwen3.8-Flash-Next-GGUF` | 262K | Heavyweight sparse MoE (125B total, ~6B active) for long-running agentic, coding, and deep reasoning tasks  |

Legend:

- 💭 — hybrid reasoning (thinking is switched per request, not per preset)
- 👀 — multimodal capabilities (vision encoder enabled)
- ⚡️ — speculative decoding enabled (Multi Token Prediction)
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

#### Weight placement

Most models fit in VRAM whole and need nothing beyond `n-gpu-layers`. `Qwen3.8-Flash-Next` does not: at
`UD-Q4_K_XL` it is 103.7 GiB against 2x 31.86 GiB of VRAM, so its preset pins placement by hand.

Two thirds of it lands off the GPUs, and the experts are only part of the reason:

- **The n-gram table never enters VRAM.** All 51B of its parameters are a single `per_layer_token_embd`
  tensor - 26.82 GiB at `IQ4_NL` - read host-side through `ggml_get_rows`, the same approach Gemma 3n
  uses for per-layer embeddings.
- **`n-cpu-moe = 24`** keeps blocks 0-23's routed experts in system RAM, leaving 40.9 GiB of weights
  resident. Decode reads ~0.70 GiB per token back over PCIe, because top-10 routing touches 10 of each
  block's 512 experts.
- **`load-mode = none`** reads that ~60 GiB of host-side tensors into memory instead of mapping them.
  llama.cpp warns that CPU tensor overrides under `mmap` are slower, and the box has 176 GiB free.
- **`tensor-split = 72,28`** - see below, this one is a trap.

The attention cache is the cheap part: only 12 of 48 layers have one, so a full 262144-token context costs
3.19 GiB at `q8_0` (6.00 GiB at `f16`), plus 0.10 GiB of indexer keys and 0.11 GiB of DeltaNet state.

> [!WARNING]
> **`tensor-split` divides by layer count, not by bytes.** `llama-model.cpp` assigns layer `il` to a
> device by comparing `il / (n_layer + 1)` against the normalized split, so it knows nothing about how
> heavy each layer is. `n-cpu-moe` makes the first N layers nearly weightless - 0.08 GiB against 1.79 GiB
> for a layer whose experts stayed on the GPU - so a split that looks balanced is not. The first attempt
> here used `52,48`, which handed GPU 0 nineteen empty layers and GPU 1 twenty-two heavy ones plus the
> output head: a single 35.35 GiB allocation on a 31.86 GiB card, and `cudaMalloc failed: out of memory`.
> Count the heavy blocks on each side, not the layers.

GPU 1 gets the smaller share for a second reason: `Qwen3-Embedding-0.6B` and `Qwen3.5-2B` both pin
`main-gpu = 1` and cost ~6 GiB whenever they are resident, and the manager only arbitrates _large_
models, so they stay loaded. With all three resident the cards sit at 30.5 GiB and 30.5 GiB of 31.86.

Measured at that setting: **571 t/s prefill, 18.6 t/s decode** on a 2222-token prompt.

`UD-IQ4_XS` (87.2 GiB) is the trade in the other direction: byte-identical apart from routed experts
(`IQ3_S`/`IQ4_NL` against `Q4_K`/`Q5_1`, ~3.9 against ~5.1 bits per weight) and the output head, which
would keep far more of them on the GPUs. Going up is not practical - `UD-Q5_K_XL` is 147.4 GiB with a
50.66 GiB n-gram table.

### Speculative decoding

Every model marked ⚡️ above uses the same mechanism — an **MTP head**: a single extra layer that shares
the base model's embeddings and runs inside the same graph. Dense, so quantization has real headroom, and
Unsloth ships one precision per model (`Q4_0`, 1.37 GB for Qwen3.8). Nothing to choose.

`Qwen3.8-Flash-Next` **has** an MTP head - the card counts it separately from the 125B, at 4B and one
layer, and the base checkpoint carries 31 `mtp.*` tensors with their own hyper-connection mixer. It still
carries no ⚡️ badge, because nothing in the stack can reach it yet:

- llama.cpp master does not implement it. The merged `qwen4exp` port declares no `NEXTN_*` tensors, so
  the converter drops the head. Support is open in
  [PR #27836](https://github.com/ggml-org/llama.cpp/pull/27836), which adds both the draft head and a
  `--mtp` converter flag.
- No published GGUF contains the head, Unsloth's included - every quant in the repo parses to zero
  `mtp.*`/`nextn.*` tensors. The head must live in the same file, not a sidecar, and the merged reader
  enforces 32-byte data alignment and an exact `split.tensors.count`, so older community exports with a
  grafted head are rejected.

So the preset sets `spec-type = none` and `spec-draft-n-max = 0` for now, and the model decodes without
speculation. When #27836 merges and a GGUF ships with the head, this becomes `spec-type = draft-mtp` with
`spec-draft-n-max = 2`: on this exact hardware (2x R9700, gfx1201, ROCm) a tester in that thread measured
**+17% decode** at depth 2 with `ubatch-size 1024` - which the stack already sets - while depths 3 and 4
came out **slower** than no speculation at all. Treat those as a starting point to re-measure, not a
result: acceptance is workload- and sampler-dependent, and the same thread reports MTP being a net loss
over RPC and greedy output diverging from the unspeculated run on ROCm.

Budget for it before flipping the switch: at 4B and `Q4_0` the head is ~2.10 GiB, plus ~0.27 GiB for one
layer of draft attention cache at the full 262144-token context. With all three models resident the cards
have 1.32 and 1.38 GiB free, so it does not fit as a preset one-liner - `n-cpu-moe` has to go to **26**,
which frees 2.93 GiB on GPU 0 and costs 0.06 GiB per token of extra host traffic (0.76 total). Against
+17% decode that trade is clearly worth taking. Note the freed room lands on GPU 0, since blocks 24-25
sit on that side of the split; if the head is placed on GPU 1 instead, `tensor-split` needs a nudge too.

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

Chat presets pin `reasoning` explicitly instead of relying on the template default. `--reasoning auto`
sends no `enable_thinking` kwarg at all, so it inherits whatever the template chose — both `Qwen3.8-27B`
and `Qwen3.8-Flash-Next` think unless told not to. `Qwen3.5-2B` pins `reasoning = off` instead, because
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
  - `Qwen3.8-Flash-Next` takes the same `low`, `medium`, `xhigh` ladder as `Qwen3.8-27B`. `high` folds into
    `xhigh`, and anything else makes the template raise, which surfaces as a 500. The preset leaves
    `reasoning = auto` and pins `reasoning-effort = medium`.
- `reasoning_budget_tokens: N` — caps the trace at `N` tokens. Only `N > 0` is honoured; `0` is ignored.

The trace comes back in `message.reasoning_content`, streamed as `delta.reasoning_content`.

`Qwen3.8-27B` and `Qwen3.8-Flash-Next` also replay every historical `<think>` block into the prompt unless
told not to — both templates default `preserve_thinking` to true — so their presets set
`reasoning-preserve = off`. `Qwen3.8-Flash-Next`'s model card argues the opposite (preserved traces help
agent loops), so it can be raised per request via `chat_template_kwargs`. Note that `--reasoning-preserve`
does not pass a kwarg of that name through: llama.cpp intercepts it and applies a dialect-normalizing layer
(`jinja::caps_apply_preserve_reasoning`) that sets `preserve_thinking`, `clear_thinking`,
`truncate_history_thinking` and `drop_thinking` together, so the one flag covers every vendor's spelling.
Prefer it over hand-written `chat-template-kwargs`, which pins a single spelling and silently stops working
if a future template renames the variable.

Turning preservation off does not touch reasoning inside the current turn: the template keeps the
`<think>` block of every assistant message after the last real user message, so a multi-step tool-calling
chain retains its full reasoning. Only traces from turns that closed before the latest user message drop.
No template branch forces reasoning retention when tools are present, so no tool-call reasoning-content
flag is needed.

In Open WebUI, either type `none` into _Chat Controls → Advanced Params → reasoning_effort_, or add a
Workspace Model over the same base model with the custom parameter `chat_template_kwargs` set to
`{"enable_thinking": false}` — unknown parameters are forwarded to llama.cpp verbatim.

### Language coverage

`Qwen3.8-27B` is strong in the languages its post-training targets — English, Chinese, French, German —
and measurably weaker in minor ones, Czech included. This is an upstream tradeoff in favour of general
intelligence, coding, and long-running agentic capability, not a defect in this stack: the quantization
(`UD-Q6_K_XL`), the `q8_0` KV cache, and the MTP drafter were each measured against the live cluster and
none of them contributes.

The competence is present but fragile. Greedy Czech output is clean and the model assigns 93–99.9% to the
correct inflection at unambiguous positions, so it effectively never samples a wrong ending. What degrades
is everything downstream of a free choice: at `temp = 1.0` roughly 22 tokens per 100 diverge from the greedy
path against 12 at `temp = 0.6`, and in a heavily inflected language every divergence commits the rest of
the clause to case, gender, number and aspect agreement that the model then has to satisfy. Broken concord
chains, mistyped terminology, and foreign script leaking into the output are the visible result.

What helps:

- **A system prompt that establishes the model as a native speaker** of the target language, with perfect
  command of it and an explicit instruction never to mix in other scripts.
- **Lower reasoning effort when generating prose** — `chat_template_kwargs: { "reasoning_effort": "low" }`.
  Deep reasoning buys nothing for writing and gives the answer more self-generated context to drift in.
- **Lower temperature**, `0.6`–`0.7`, which roughly halves the divergence rate above.

What does not help: forcing the model to _think_ in the target language. Its traces come back in English
even when the prompt demands otherwise, and instructing it to reason in Czech does not improve the output.

Set these per model rather than globally — a Workspace Model over the same base model (above) carries a
system prompt and parameter overrides without touching the preset or reloading weights.

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
