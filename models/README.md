# 🧠 Models

Panther Minor serves two modalities, each with its own catalog, and both can run
[side by side](#-recommended-workflows):

- **`llm.config.json`** (+ `llm.schema.json`) — large language models served by `llama.cpp`
- **`t2i.config.json`** (+ `t2i.schema.json`) — text-to-image models served by `stable-diffusion.cpp`

## 📦 Shared model cache

Weights live in one shared Hugging Face cache, `models/.huggingface`, mounted into both containers. Each file
is stored at its repository-relative path (`<repository>/<file>`), so a file used by more than one model is
kept **only once** and same-named files from different repositories never collide.

```bash
./bin/panther-minor models llm|t2i download|remove <model>   # Fetch missing files / delete only unshared ones
./bin/panther-minor models prune                             # Reclaim files no config references anymore
```

## 📚 Large language models (`llm.config.json`)

Served by the local `llama.cpp` cluster with an OpenAI-compatible API.

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

Models are defined in `llm.config.json` (schema in `llm.schema.json`) and served through `llama-cpp/preset.ini`
[presets](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#model-presets), with `llama-cpp` in
[router mode](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#using-multiple-models). A model's
**`components`** are its weight files — main weight first, then extras like `mmproj-*` vision encoders or
`mtp-*` draft models — by Hugging Face `repository` + `file`, possibly across repositories.

#### Weight placement

Most models fit VRAM whole; only `n-gpu-layers` matters. A model larger than total VRAM
(`Qwen3.8-Flash-Next` at `UD-Q4_K_XL` is 103.7 GiB against 2x 31.86 GiB) needs manual placement: `n-cpu-moe`
keeps the first N blocks' experts in RAM, `tensor-split` balances the rest across cards, and `load-mode = none`
means "no special loading mode" — mmap stays on, so most of the process stays file-backed. Tune by
measurement, not arithmetic, and note that small models pinned to a `main-gpu` shift the balance while
resident, since the manager only arbitrates _large_ models.

> [!WARNING]
> **`tensor-split` divides by layer count, not bytes.** `llama-model.cpp` assigns layer `il` to a device via
> `il / (n_layer + 1)` against the normalized split, ignoring per-layer weight, and `n-cpu-moe` makes the
> first N layers nearly weightless. So a balanced-looking split isn't: `52,48` put nineteen empty layers on
> one card and twenty-two heavy ones plus the output head on the other, overflowing it. Count heavy blocks.

#### Benchmarking

Throughput ramps for ~7 requests after a model becomes resident, and each `llama-server` process settles into
one of several discrete throughput modes per load, so `bench` defaults to `--warmups 8` and every preset
comparison needs `--loads 3`. Results append to `bench.log`; the procedure, pitfalls and per-knob guidance
live in the [`tune-preset` skill](../.agents/skills/tune-preset/SKILL.md).

> [!TIP]
> **Neither host CPU nor DRAM bandwidth binds MoE decode at this kind of placement.** Cutting generation to 2
> pinned cores (2.6x less host compute _and_ bandwidth) cost 7.5%, a co-runner eating all remaining DRAM
> bandwidth cost 0.4%, and halving DIMM count for a higher rated clock changed nothing. Faster RAM does not
> pay, and `n-cpu-moe` can be _raised_ to free VRAM cheaply. Flips for a dense model resident in RAM.

Sweeping one placement knob at a time yields a linear cost model — for `Qwen3.8-Flash-Next`,
`ms/pass = 54.0 + 1.60 * n-cpu-moe` (R² = 0.975). The **slope** is just bytes — 1.60 ms/block is what those
experts cost at the DRAM ceiling this box actually reaches (45.3 GiB/s, measured; a single core already gets
37.3 GiB/s), so there is no per-block handoff overhead hiding in it. The **intercept** is only the fit
extrapolated to `n-cpu-moe = 0`; it is not the same quantity as a bare pass at the deployed placement (which
still streams 28 blocks), so don't read the two as cross-confirming. What matters for procurement is that
only the slope term is bandwidth-exposed: +20% DRAM bandwidth is capped at **≤7.5%** end to end, which is why
the two physical memory experiments came back flat.

> [!WARNING]
> **Benchmark at the context length you work at.** Short-prompt numbers flatter these models badly. For
> `Qwen3.8-Flash-Next`, a plain (`spec-type = none`) token costs 54.6 ms at a 50-token prompt, 69.4 ms at 40K
> and 81.8 ms at 85K — near-linear at **~0.35 ms per 1K**, measured at batch 1 so no acceptance effect is
> mixed in. MTP acceptance decays over the same span independently (70% → 45% → 34%, with a per-line nonce so
> `--cache-reuse` cannot match KV chunks between runs). The two compound: **23.4 t/s short, 16.4 at 40K, 13.6
> at 85K**. Prefill on uncacheable prompts runs 343 t/s at 40K and 265 t/s at 85K, so first token lands ~2 min
> and ~5 min in respectively.
>
> MTP still pays at every length, but its margin narrows as acceptance falls — **+30% short, +13.5% at 40K,
> +11.5% at 85K** — so depth and drafter decisions made at short context do not transfer upward.

### Speculative decoding

Most ⚡️ models use an **MTP head**: one extra dense layer sharing the base model's embeddings, run in-graph,
and Unsloth ships a single `Q4_0` quant per model — nothing to choose. `Qwen3.8-Flash-Next` is the exception,
with a **full MoE block** (512 experts, 2.58 GiB) shipped separately under `MTP/` in six variants. The stack
uses `shared-Q8_0`: `shared-` variants borrow the target's `token_embd`/`output.weight` rather than carrying
their own, saving 1.27 GiB, but the loader takes a raw pointer into the target's tensor map, so the head must
land on whichever card holds `output.weight` — the last slot of `tensor-split`. Offloading experts to make room
for it is structurally sound: a verify pass reads them **once** but settles ~2.5 tokens, so `n-cpu-moe` hurts
_less_ under speculation than without it. Skip MTP for concurrent serving (0.81-0.87x at concurrency 8), and
confirm the head actually runs via `timings.draft_n` / `draft_n_accepted`.

Priced in isolation on `Qwen3.8-Flash-Next` by flipping `spec-type` between `draft-mtp` and `none` in one
session, the head is worth **+30.6%** at the production sampler — 54.6 → 42.0 ms/token, or 18.3 → 23.9 t/s. In
per-pass terms a speculative pass costs ~39 ms more than a plain token (93.9 vs 54.6) and returns ~1.25 extra
tokens. Splitting that 39 ms between the two draft forwards and the wider verify batch requires a model rather
than a measurement, so treat any finer breakdown as estimated. Worth noting: a spec-off pass is strikingly
repeatable (σ ≈ 0.1 ms/token), so nearly all run-to-run spread in speculative throughput is acceptance, not
the machine.

> [!IMPORTANT]
> **These heads do not run on mainline llama.cpp.** Upstream declares no `NEXTN_*` tensors for `qwen4exp`
> (still true at `d08c787`), so it drops the head at conversion and silently ignores `spec-draft-model`. The
> build is pinned to [unslothai/llama.cpp#144](https://github.com/unslothai/llama.cpp/pull/144) at commit
> `586b15ef` — see [`.env.example`](../.env.example). Do **not** use that fork's prebuilt `*-mix-*` releases:
> they predate the `qwen4exp` port and cannot load this model at all.

#### Draft depth

`spec-draft-n-max` sets tokens proposed per round. Acceptance decays geometrically, so the optimum is where the
marginal accepted token stops paying for its draft-and-sample cycle — and it is **sampler-dependent**: greedy
accepts far more than the `temp = 1.0` these presets serve. Depth stays at **2**.

Compare depths **structurally**, not on tok/s: acceptance swings 35-75% between otherwise identical runs, so
tok/s needs impractically many samples to separate neighbouring depths (depth 2 vs 3 differs by 1.8 t/s
against σ = 1.7). Per-pass cost and tokens-per-pass are far tighter — over 6 runs on one load each, depth 3
cost **+19.8%** per pass to settle only **+9.9%** more tokens. Read that as indicative rather than decisive:
one load per arm sits inside the per-process mode spread described above, and an earlier 3-load comparison put
depth 2 vs 3 at a wash. Depth 4 was also a single-load result (−7% t/s) but sat at the bottom of the observed
acceptance range.
Always measure at the sampler you serve — the
[`tune-preset` skill](../.agents/skills/tune-preset/SKILL.md) has the worked example and the metrics endpoint.

### GPU split mode

`split-mode` spreads a model over GPUs, and the choice is not free on ROCm. **`tensor`** slices every layer
across every GPU, fastest for **dense** models but paying an all-reduce per row-parallel projection — and it
silently disables backend (GPU) sampling (which drags `spec-draft-n-max` down) plus `llama_params_fit`, so
placement must be pinned by hand. Its all-reduce needs RCCL, whose bundled "internal" implementation is
CUDA-only: a build missing `-DGGML_HIP_RCCL=ON` falls back to a slower meta backend, worth ~20% of the forward
pass on `Qwen3.8-27B`. **`layer`** puts whole layers per GPU — no all-reduce, slower dense decode, the right
fit for sparse MoE or uneven topologies. **`none`** is single-GPU, with `main-gpu`.

### Management

```bash
./bin/panther-minor models llm list|download|remove <model>   # Weight files (-f forces re-download)
./bin/panther-minor models llm load|unload|bench <preset>     # Serving and measurement
```

`download`/`remove` take a **model name** from the table above, removing only unshared files;
`load`/`unload`/`bench` take a **preset name** from [`llama-cpp/preset.ini`](../llama-cpp/preset.ini), what
llama-server actually serves. Presets map 1:1 to models, and thinking is a per-request switch, so changing
reasoning mode never reloads weights.

### Reasoning control

Presets pin `reasoning` explicitly, since `auto` inherits the template default; `Qwen3.5-2B` pins `off` because
Open WebUI drives it as the task model for titles, tags and query rewriting, which must never think.
Per-request switches, in order of preference:

- `chat_template_kwargs: { "enable_thinking": true | false }` — works both directions regardless of preset;
  sent by the harness configs in [`harnesses/`](../harnesses/README.md).
- `chat_template_kwargs: { "reasoning_effort": … }` — Qwen3.8 models take `low`/`medium`/`xhigh` (`high` folds
  into `xhigh`, unknown values raise). On `Qwen3.8-27B`, `"none"` disables thinking only while
  `reasoning = auto`; `reasoning = on` ignores it and leaks raw `<think>` tags into `content`.
- `reasoning_budget_tokens: N` — caps the trace; only `N > 0` is honoured.

Traces arrive in `message.reasoning_content` (streamed as `delta.reasoning_content`). Large models default
`preserve_thinking` to true, so presets set `reasoning-preserve = off` — prefer that flag over hand-written
`chat-template-kwargs`, which breaks silently if a template renames its variable. It only drops closed-turn
traces, so tool-calling chains retain full reasoning. In Open WebUI, type `none` into _Chat Controls →
Advanced Params → reasoning_effort_, or add a Workspace Model with
`chat_template_kwargs: {"enable_thinking": false}`.

### Language coverage

Qwen3 models are strongest in English and Chinese and weaker in minor languages — an upstream post-training
tradeoff: quantization, `q8_0` KV cache and the MTP drafter were each measured and none contributes. In
heavily inflected languages greedy output is clean and only _sampled_ choice degrades, each divergence
committing the clause to case/gender/number/aspect agreement. Lower `temp` to `0.6`-`0.7` and add a
native-speaker system prompt forbidding script mixing, per model via a Workspace Model.

---

## 🎨 Text-to-image models (`t2i.config.json`)

Served by [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)'s `sd-server`, exposing an
OpenAI-compatible image API on port `8001`.

| Model            | Base                          | Notes                                                                                                             |
| ---------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `Ideogram-4`     | `leejet/ideogram-4-GGUF`      | Strong prompt adherence and text rendering; uses a Qwen3-VL-8B encoder + Flux2 VAE                                |
| `Qwen-Image-2.1` | `unsloth/Qwen-Image-2.1-GGUF` | 7B photorealistic generation, native transparency (RGBA) and text rendering (Q8_0); Qwen3-VL-8B encoder + own VAE |

> [!IMPORTANT]
> Ideogram 4 requires JSON prompts and will most likely fail on a pure text prompt — see its
> [prompting guide](https://github.com/ideogram-oss/ideogram4/blob/main/docs/prompting.md#prompting-guide). The
> `ideogram4-prompt` skill (`.agents/skills/ideogram4-prompt/SKILL.md`) generates valid JSON prompts from
> natural language, but needs a sufficiently capable chat model to drive it.

### Configuration

Models are defined in `t2i.config.json` (schema in `t2i.schema.json`). **`components`** are the weight files a
model needs (diffusion, optional unconditional diffusion, LLM text encoder, VAE), and models list only what
they use — Ideogram 4 has a separate unconditional diffusion model, Qwen-Image doesn't. Both share the same
Qwen3-VL-8B encoder file, so it is downloaded once and `remove` keeps it while the other model needs it.
**`args`** _(optional)_ carries extra `sd-server` flags for per-model sampling defaults (e.g. `--cfg-scale` and
`--steps` for Qwen-Image); `load` writes them to `SD_CPP_MODEL_ARGS` in `.env`, so tuning switches with the model.

### Management

```bash
./bin/panther-minor models t2i list|download|remove <model>   # Components (-f forces re-download)
./bin/panther-minor models t2i load [-e] <model>              # Serve it (-e dedicates a GPU); unload stops sd-server
```

`sd-server` loads exactly **one** model per process, so `load` rewrites the active-model variables in `.env`
and recreates the container — switching never leaves two models in VRAM. It is entirely a CLI operation:
`sd-server` ignores the model id in the request, so **Open WebUI needs no changes**. Leave its image model
field at `default`, never touch admin image settings, and treat `IMAGE_GENERATION_MODEL` as a label — the
Images panel lists only the loaded model, all `sd-server` reports.

### GPU assignment

By default `load` only swaps the model, leaving GPU assignment untouched so the LLMs keep all GPUs — the right
mode for the [everyday workflow](#everyday-chat-with-occasional-images-no-gpu-switching). For
[heavy image sessions](#heavy-image-sessions-dedicate-a-gpu), `load --exclusive` shrinks the LLMs from
`LLAMA_CPP_GPUS_STANDALONE` to `LLAMA_CPP_GPUS_SHARED` (→ `ROCM_VISIBLE_DEVICES`), freeing
`SD_VISIBLE_DEVICES` for `sd-server` alone; `unload` restores it. Both recreate `llama-cpp`, so resident LLMs
reload lazily — switch modes per session, not per image. All four variables live in `.env` (documented in
`.env.example`) and default to a two-GPU box; edit them to match your topology.

---

## 🧭 Recommended workflows

LLMs and image generation share the same GPUs, so running heavyweight models of both kinds at once contends
for VRAM. `sd-server` always runs on `SD_VISIBLE_DEVICES` (GPU 1), which also hosts the pinned
`Qwen3-Embedding-0.6B` and `Qwen3.5-2B` (~5.8 GiB together). Pick the workflow that matches your session.

### Image model footprint

Measured on GPU 1 at 1024×1024 (Open WebUI's `IMAGE_SIZE`), weights offloaded to RAM between generations:

| Image model               | Weights (RAM) | Peak VRAM, GPU to itself | Generation |
| ------------------------- | ------------: | -----------------------: | ---------: |
| `Qwen-Image-2.1` (Q8_0)   |      12.1 GiB |                  8.6 GiB |       77 s |
| `Ideogram-4` (Q4_0)       |      15.0 GiB |                 10.7 GiB |       88 s |
| `Qwen-Image-2512` (Q8_0)¹ |      25.0 GiB |                 21.3 GiB |      196 s |

¹ Replaced by `Qwen-Image-2.1`; kept for comparison (40 steps against 2.1's 20, weights summed from its
files). The other weights are `sd-server`'s own totals.

When the image GPU has less free VRAM than the peak, `sd-server` degrades instead of failing: it streams the
diffusion weights in segments and tiles the VAE decode. At ~2 GiB free it cannot fit a segment and returns
HTTP 500 at once; the LLMs keep serving. Measured with the pinned small models resident:

| Large chat model     | GPU 1 used before image | `Qwen-Image-2.1`           | `Ideogram-4`                |
| -------------------- | ----------------------: | -------------------------- | --------------------------- |
| `Qwen3.8-27B`        |                25.3 GiB | ✅ 85 s (segmented, tiled) | ✅ 111 s (segmented, tiled) |
| `Qwen3.6-35B-A3B`    |                30.2 GiB | ❌ HTTP 500                | ❌ HTTP 500                 |
| `Qwen3.8-Flash-Next` |                31.8 GiB | ❌ HTTP 500                | ❌ (less room than 35B-A3B) |

Load the chat model **before** generating, as the everyday flow does anyway: a large LLM loaded while
`sd-server` holds its peak finds that VRAM taken.

### Everyday: chat with occasional images (no GPU switching)

Load an image model once (`./bin/panther-minor models t2i load <model>`) and leave GPU assignment alone — no
reassignment, no restarts, no cleanup, and `stable-diffusion.cpp` holds VRAM only while producing an image.
The chat model's only role is **authoring the prompt**, so match it to the loaded image model:

| Loaded image model | Prompting                                  | Recommended chat model        | Why                                                                                     |
| ------------------ | ------------------------------------------ | ----------------------------- | --------------------------------------------------------------------------------------- |
| `Qwen-Image-2.1`   | Plain text                                 | `Qwen3.5-2B` to `Qwen3.8-27B` | Any co-resident model can write a plain prompt; a larger one writes richer descriptions |
| `Ideogram-4`       | Structured JSON (`ideogram4-prompt` skill) | `Qwen3.8-27B`                 | Small models can't drive the JSON-prompt skill; larger ones leave the image GPU no room |

### Heavy image sessions: dedicate a GPU

For many images, or a pairing the shared GPUs cannot fit — **`Qwen3.6-35B-A3B` or `Qwen3.8-Flash-Next` next to
any image model** — give image generation a GPU of its own. Next to `Qwen3.8-27B` it also avoids segmented
streaming and tiling, which cost +10% (`Qwen-Image-2.1`) to +26% (`Ideogram-4`) per image. See
[GPU assignment](#gpu-assignment) for the mechanics.

```bash
./bin/panther-minor models t2i load --exclusive <model>   # LLMs shrink onto their own GPU(s), sd-server gets a dedicated one
./bin/panther-minor models t2i unload                     # Done: sd-server stops, all GPUs return to the LLMs
```
