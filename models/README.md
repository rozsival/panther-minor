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

| Model                         | Base                              | Ctx  | Purpose                                                                        |
| ----------------------------- | --------------------------------- | ---- | ------------------------------------------------------------------------------ |
| `Qwen3.8-27B` 💭 👀 ⚡️️        | `unsloth/Qwen3.8-27B-GGUF`        | 262K | Primary dense model, general reasoning to multimodal                           |
| `Qwen3.6-35B-A3B` 💭 👀 ⚡️    | `unsloth/Qwen3.6-35B-A3B-GGUF`    | 262K | Versatile MoE, specialized multimodal reasoning + fast problem solving         |
| `Qwen3.5-2B` 💭 👀️ ⚡️         | `unsloth/Qwen3.5-2B-GGUF`         | 33K  | Lightweight dense, fast inference, scaffolding, image-gen chats                |
| `Qwen3-Embedding-0.6B` 🪶     | `Qwen/Qwen3-Embedding-0.6B-GGUF`  | 16K  | Lightweight embedding model, RAG pipelines only                                |
| `Qwen3.8-Flash-Next` 💭 👀 ⚡️ | `unsloth/Qwen3.8-Flash-Next-GGUF` | 262K | Heavyweight sparse MoE (125B total, ~6B active), long agentic/coding/reasoning |

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

| Setting                | Value                           | Note                                                                                                |
| ---------------------- | ------------------------------- | --------------------------------------------------------------------------------------------------- |
| n-gram table           | 26.82 GiB `IQ4_NL`, host-side   | single `per_layer_token_embd` tensor via `ggml_get_rows`, never VRAM (Gemma 3n technique)           |
| `n-cpu-moe = 28`       | 35.15 GiB resident              | blocks 0-27 experts stay in RAM; 26 measured no faster and 24 fails to load — see Throughput modes  |
| `load-mode = none`     | mmap, not a read-in             | `none` means "no special loading mode"; mmap stays on — 46 GiB of the process is file-backed        |
| `tensor-split = 78,22` | —                               | balances heavy blocks, not layer count — see WARNING                                                |
| MTP head               | 2.58 GiB `shared-Q8_0` on GPU 1 | must sit with `output.weight`, whose tensor it borrows — see Speculative decoding                   |
| KV @ 262144 ctx        | 3.19 GiB `q8_0` (6.00 `f16`)    | only 12/48 layers cache; +0.10 GiB indexer keys, +0.11 GiB DeltaNet                                 |
| VRAM, all 3 resident   | 29.53 / 30.29 of 31.86 GiB      | measured after the retune; solver predicted 29.48 / 30.40 — within 0.11 GiB on both cards           |
| Measured, greedy       | 43.8 t/s at depth 2             | `bench` is temp 0; depth 3 reaches 57.4 there but not in production — see Draft depth               |
| Measured, `temp = 1.0` | 25.4 t/s (56-62% accepted)      | production sampling, 768 tokens, 3 loads; depth 3 is a wash here (25.2) — benchmark at your sampler |

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

#### Throughput modes

Two properties of this model make single-shot numbers meaningless, so `bench` defaults to
`--warmups 8` and every preset comparison needs `--loads 3`:

- **Throughput ramps for ~7 requests** after a model becomes resident. One discarded warm-up measures the
  ramp, not the steady state — it under-reported this stack by 54% (44.4 vs. 68.4 t/s on the same config).
- **Each `llama-server` process can settle into one of several discrete modes** spanning ~39-69 t/s under
  greedy benchmarking. A mode is stable to within 1% for the life of the process and re-rolled on every
  load, so one load cannot resolve anything smaller than ~25%. The variance lives in the draft path, not
  the base model: two loads produced byte-identical output (same `md5`) at 47.3 vs. 56.4 t/s, differing only
  in how many drafts were wasted (761 vs. 640 proposals for the same 512 tokens). It is also largely a
  **greedy-path** phenomenon — under production sampling both depths 2 and 3 held a ~7% band across loads.
  Ruled out as causes: page placement (48 GiB RSS / 46 GiB file-backed every load), disk paging (19 MiB of
  NVMe reads per run), CCD pinning (threads split ~50/50 on fast _and_ slow loads), VRAM placement
  (28/25 GiB, zero offload failures), GPU clocks (`sclk ≈ 2570`, `fclk ≈ 2047`, stable), `ignore_eos`, and
  `load-mode`. Root cause unknown, so keep `--loads 3` for every comparison.

**Neither host CPU nor DRAM bandwidth is the binding constraint.** Measured with `bench --loads 3`, all
inside the noise band of the greedy baseline: pinning 12 threads to the 12 physical
cores (`cpu-range = 0-11`, `cpu-strict = 1`) → 58.1; 11 threads → 57.9; **6 threads on one CCD → 56.5**;
`poll = 0` → 57.8. Restricting generation to **2 pinned cores**, which caps host read bandwidth at ~17 GB/s
(38% of the 44.8-46.2 GB/s this box achieves), costs only **-7.5%** (53.0 t/s). So a 2.6x cut in both host
compute and bandwidth buys back 7.5%, implying a bandwidth elasticity near 0.1 — DDR5-3600 → 4400 (+23%
peak) is worth ~1-2%, and there is no overthreading to fix. The GPUs idling at 30-36% / 14-24% busy while
"11.8 of 12 cores are pegged" is ggml's spin-wait, not work: `--poll 0` and 6 threads prove the host side
has roughly 2x headroom. The remaining limit is the serial draft-verify chain on the GPUs.

Two consequences: EXPO/DRAM overclocking is not worth the boot risk on this box (4x48 GiB, 2DPC, dual-rank
cannot train above the JEDEC 3600 fallback anyway), and `n-cpu-moe` can be _raised_ to free VRAM at little
throughput cost if the sidekicks or image generation ever need the room. The `~0.81 GiB/token` above is
derived, not measured, and overstates real traffic: at 57 t/s it would require more bandwidth than the
machine has. H2D DMA measures 28.8 GB/s per card over Gen5 x16.

### Speculative decoding

Most ⚡️ models use an **MTP head** that is one extra dense layer sharing the base model's embeddings, run
in-graph; Unsloth ships one `Q4_0` quant per model (1.37 GB for Qwen3.8) — nothing to choose.

`Qwen3.8-Flash-Next` now has one too, but on different terms. Its head is a **full MoE block** — 512 experts,
2.49 GiB of the 2.58 GiB — not a dense layer, and it ships as a separate file under `MTP/` rather than inside
the weights. Six variants; the stack uses **`mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf`**:

- **`shared-`** carries no `token_embd`/`output.weight` and borrows the target's, saving 1.27 GiB. The loader
  takes a raw pointer into the target's tensor map, so the head must be placed on whichever card holds
  `output.weight` — the last slot of `tensor-split`, i.e. GPU 1. This is what forced the split retune.
- **`Q8_0`** over `Q4_K_M`: 66.1% vs. 64.4% acceptance, and a draft step is dominated by the output
  projection, which executes cheaper at 8 bits — `BF16` is both bigger and slower for the same reason.
- Self-contained variants exist for builds without borrowing support; they cost 1.27 GiB for nothing here.

> [!IMPORTANT]
> **These heads do not run on mainline llama.cpp.** Upstream declares no `NEXTN_*` tensors for `qwen4exp`
> (still true at `d08c787`), so it drops the head at conversion and silently ignores `spec-draft-model`. The
> build is pinned to [unslothai/llama.cpp#144](https://github.com/unslothai/llama.cpp/pull/144) at commit
> `586b15ef` — see [`.env.example`](../.env.example). Do **not** use that fork's prebuilt `*-mix-*` releases:
> they are cut from a base predating the `qwen4exp` port and cannot load this model at all.

Placement cost: 2.58 GiB head + ~0.07 GiB draft KV, against 1.32/1.38 GiB free. `n-cpu-moe` goes 24 → **28**
and the split 72,28 → **78,22**, moving four blocks of experts to RAM to clear room on GPU 1. The trade is
structurally sound: a verify pass reads those experts **once** but settles ~2.5 tokens, so offloading hurts
_less_ under speculation than without it. The `18.6 → 23.6 t/s` that once justified it was measured with a
single warm-up and one load; production sampling now measures **25.4 t/s**. Depth stays at **2**, re-measured
at both samplers — see Draft depth. Verify the head
is actually running (mainline would silently no-op) — `timings.draft_n` / `draft_n_accepted` per response, or:

```
draft acceptance = 0.66139 (325 accepted / 491 generated), mean len = 2.76
```

Skip MTP for concurrent serving: measured 0.81-0.87x at concurrency 8, since a busy model has no idle capacity
for a draft to exploit. The win is at concurrency 1.

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

Measured on `Qwen3.8-Flash-Next` twice — once with `bench` (greedy, `--tokens 256 --warmups 8 --runs 2
--loads 10`), once at the **production sampler this preset serves** (`temp = 1.0`, `top-k 20`, `top-p 0.95`,
768 tokens, 3 loads):

| `spec-draft-n-max` | greedy median | greedy range | `temp = 1.0` median | drafts issued | accepted |
| ------------------ | ------------- | ------------ | ------------------- | ------------- | -------- |
| **2**              | 46.1 t/s      | 38.8-64.3    | **25.4 t/s**        | 2152          | 59%      |
| 3                  | 57.4 t/s      | 56.7-58.2    | 25.2 t/s            | 2611          | 56%      |
| 4                  | 57.5 t/s      | 31.6-58.0    | not measured        | —             | —        |

**Depth stays at 2.** Depth 3's +24% is a greedy artifact that does not survive real sampling: it issues
~20% more drafts at lower acceptance and the two cancel, leaving 25.2 vs. 25.4 t/s — a wash. The same held
in real coding-harness use on `Qwen3.8-27B`, where depth 3 produced no observable gain. This is the
cautionary case for the whole section: a 24% "win" that is entirely an artifact of the benchmark's sampler.
Note also that the greedy mode lottery (38.8-64.3 at depth 2) does **not** appear under production sampling,
where both depths held a ~7% band — so it, too, is largely a greedy-path phenomenon.

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
