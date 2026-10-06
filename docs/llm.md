# 🦙 LLM Serving

> `llama-cpp` runs `llama-server` in router mode: every model is a preset in `llama-cpp/preset.ini`, loaded on
> demand and served under one OpenAI-compatible API behind `llama-manager`. This page covers presets, weight
> placement, measurement, speculative decoding, multi-GPU split modes and per-request reasoning control.

**Related:** [Models](models.md) · [GPU power & VRAM](gpu-management.md) · [Coding harnesses](harnesses.md) ·
[Monitoring](monitoring.md) · [`tune-preset` skill](../.agents/skills/tune-preset/SKILL.md)

---

## ⚙️ Configuration

Models are defined in `models/llm.config.json` (schema in `models/llm.schema.json`) and served through
`llama-cpp/preset.ini` [presets](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#model-presets), with
`llama-cpp` in [router mode](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#using-multiple-models). A
model's **`components`** are its weight files — main weight first, then extras like `mmproj-*` vision encoders or
`mtp-*` draft models.

| Layer               | Where                    | Scope                                                                      |
| ------------------- | ------------------------ | -------------------------------------------------------------------------- |
| Weights             | `models/llm.config.json` | Which files to download per model                                          |
| Per-model runtime   | `llama-cpp/preset.ini`   | Context, cache types, placement, sampling, reasoning, speculative decoding |
| Server-wide runtime | `.env` (`LLAMA_CPP_*`)   | Batch sizes, RAM cache, max resident models, parallel slots                |
| Large-model list    | `llama-cpp/models.js`    | Models `llama-manager` arbitrates VRAM for                                 |

### Weight placement

Most models fit VRAM whole; only `n-gpu-layers` matters. A model larger than total VRAM (`Qwen3.8-Flash-Next` at
`UD-Q4_K_XL` is 103.7 GiB against 2x 31.86 GiB) needs manual placement:

| Knob               | Effect                                                                              |
| ------------------ | ----------------------------------------------------------------------------------- |
| `n-cpu-moe = N`    | Keeps the first N blocks' experts in system RAM                                     |
| `tensor-split`     | Balances the remaining layers across cards                                          |
| `load-mode = none` | "No special loading mode" — mmap stays on, so most of the process stays file-backed |

Tune by measurement, not arithmetic, and note that small models pinned to a `main-gpu` shift the balance while
resident, since the manager only arbitrates _large_ models.

> [!WARNING]
> **`tensor-split` divides by layer count, not bytes.** `llama-model.cpp` assigns layer `il` to a device via
> `il / (n_layer + 1)` against the normalized split, ignoring per-layer weight, and `n-cpu-moe` makes the
> first N layers nearly weightless. So a balanced-looking split isn't: `52,48` put nineteen empty layers on
> one card and twenty-two heavy ones plus the output head on the other, overflowing it. Count heavy blocks.

## 🎛️ Management

```bash
./bin/panther-minor models llm load <preset>      # Load into llama-server
./bin/panther-minor models llm unload <preset>    # Free its VRAM
./bin/panther-minor models llm bench <preset>     # Measure decode/prefill, append to models/bench.log
```

`load`/`unload`/`bench` take a **preset name** from `llama-cpp/preset.ini`; `download`/`remove` take a model name
([Models](models.md#-managing-weights)). Presets map 1:1 to models, and thinking is a per-request switch, so changing
reasoning mode never reloads weights. Requests for an unloaded preset also load it on demand.

## 📏 Benchmarking

Throughput ramps for ~7 requests after a model becomes resident, and each `llama-server` process settles into one of
several discrete throughput modes per load. `bench` therefore defaults to `--warmups 8`, and every preset comparison
needs `--loads 3`:

```bash
./bin/panther-minor models llm bench --loads 3 --tokens 512 Qwen3.8-Flash-Next
```

Results append to `models/bench.log`; the procedure, pitfalls and per-knob guidance live in the
[`tune-preset` skill](../.agents/skills/tune-preset/SKILL.md).

> [!TIP]
> **Neither host CPU nor DRAM bandwidth binds MoE decode at this kind of placement.** Cutting generation to 2
> pinned cores (2.6x less host compute _and_ bandwidth) cost 7.5%, a co-runner eating all remaining DRAM
> bandwidth cost 0.4%, and halving DIMM count for a higher rated clock changed nothing. Faster RAM does not
> pay, and `n-cpu-moe` can be _raised_ to free VRAM cheaply. Flips for a dense model resident in RAM.

### Placement cost model

Sweeping one placement knob at a time yields a linear cost model — for `Qwen3.8-Flash-Next`,
`ms/pass = 54.0 + 1.60 * n-cpu-moe` (R² = 0.975).

- The **slope** is just bytes — 1.60 ms/block is what those experts cost at the DRAM ceiling this box actually
  reaches (45.3 GiB/s, measured; a single core already gets 37.3 GiB/s), so there is no per-block handoff overhead
  hiding in it.
- The **intercept** is only the fit extrapolated to `n-cpu-moe = 0`; it is not the same quantity as the bare pass
  measured at `n-cpu-moe = 28` (which still streams 28 blocks), so don't read the two as cross-confirming.

What matters for procurement is that only the slope term is bandwidth-exposed: +20% DRAM bandwidth is capped at
**≤7.5%** end to end, which is why the two physical memory experiments came back flat.

### Context length

> [!WARNING]
> **Benchmark at the context length you work at.** Short-prompt numbers flatter these models badly.

Measured on `Qwen3.8-Flash-Next` at batch 1, with a per-line nonce so `--cache-reuse` cannot match KV chunks between
runs:

| Prompt length | Plain token (`spec-type = none`) | MTP acceptance | Decode with MTP | MTP gain | Prefill (uncached) | First token |
| ------------: | -------------------------------: | -------------: | --------------: | -------: | -----------------: | ----------: |
|     50 tokens |                          54.6 ms |            70% |        23.4 t/s |     +30% |                  — |           — |
|           40K |                          69.4 ms |            45% |        16.4 t/s |   +13.5% |            343 t/s |      ~2 min |
|           85K |                          81.8 ms |            34% |        13.6 t/s |   +11.5% |            265 t/s |      ~5 min |

Per-token cost grows near-linearly at **~0.35 ms per 1K** of context, and MTP acceptance decays independently over the
same span; the two compound. MTP still pays at every length, but its margin narrows, so depth and drafter decisions
made at short context do not transfer upward.

## ⚡ Speculative decoding

Most ⚡️ models use an **MTP head**: one extra dense layer sharing the base model's embeddings, run in-graph, and
Unsloth ships a single `Q4_0` quant per model — nothing to choose.

`Qwen3.8-Flash-Next` is the exception, with a **full MoE block** (512 experts) shipped separately under `MTP/` in six
variants. The stack uses the self-contained `Q8_0` (3.85 GiB). The `shared-` variants are 1.27 GiB smaller because
they borrow the target's `token_embd`/`output.weight`, but only the `unslothai/llama.cpp#144` fork could load them:
upstream requires `token_embd` in the head and has no cross-GGUF borrowing, so they fail with
`token_embd.weight not found`. The head inherits the target's `tensor-split` and lands on the last slot, GPU 1.
Offloading experts to make room for it is structurally sound: a verify pass reads them **once** but settles ~2.5
tokens, so `n-cpu-moe` hurts _less_ under speculation than without it.

Skip MTP for concurrent serving (0.81-0.87x at concurrency 8), and confirm the head actually runs via
`timings.draft_n` / `draft_n_accepted`.

Priced in isolation on `Qwen3.8-Flash-Next` by flipping `spec-type` between `draft-mtp` and `none` in one session, the
head was worth **+30.6%** at the production sampler — 54.6 → 42.0 ms/token, or 18.3 → 23.9 t/s. In per-pass terms a
speculative pass costs ~39 ms more than a plain token (93.9 vs 54.6) and returns ~1.25 extra tokens. Splitting that
39 ms between the two draft forwards and the wider verify batch requires a model rather than a measurement, so treat
any finer breakdown as estimated. A spec-off pass is strikingly repeatable (σ ≈ 0.1 ms/token), so nearly all
run-to-run spread in speculative throughput is acceptance, not the machine. These and every other MTP figure on this
page were measured on the `unslothai/llama.cpp#144` fork with the `shared-Q8_0` head at `n-cpu-moe = 28`. The
upstream v0.6.0 build with the self-contained head and `n-cpu-moe = 29` is faster on both ends — ~+100 t/s prefill
and ~+5 t/s decode in Grafana — but has not been through `models llm bench` yet.

> [!IMPORTANT]
> **MTP for `qwen4exp` needs `llama.cpp` v0.6.0 or newer** ([ggml-org/llama.cpp#29761](https://github.com/ggml-org/llama.cpp/pull/29761));
> older mainline builds drop the head and silently ignore `spec-draft-model`. The main UD-Q4_K_XL shards are
> unaffected, but Unsloth re-cut the self-contained heads for it on 2026-10-05 — a cached
> `MTP/mtp-Qwen3.8-Flash-Next-Q8_0.gguf` from before that date must be re-downloaded.

### Draft depth

`spec-draft-n-max` sets tokens proposed per round. Acceptance decays geometrically, so the optimum is where the
marginal accepted token stops paying for its draft-and-sample cycle — and it is **sampler-dependent**: greedy accepts
far more than the `temp = 1.0` these presets serve. Depth stays at **2**.

Compare depths **structurally**, not on tok/s: acceptance swings 35-75% between otherwise identical runs, so tok/s
needs impractically many samples to separate neighbouring depths (depth 2 vs 3 differs by 1.8 t/s against σ = 1.7).
Per-pass cost and tokens-per-pass are far tighter — over 6 runs on one load each, depth 3 cost **+19.8%** per pass to
settle only **+9.9%** more tokens. Read that as indicative rather than decisive: one load per arm sits inside the
per-process mode spread described above, and an earlier 3-load comparison put depth 2 vs 3 at a wash. Depth 4 was also
a single-load result (−7% t/s) but sat at the bottom of the observed acceptance range.

Always measure at the sampler you serve — the [`tune-preset` skill](../.agents/skills/tune-preset/SKILL.md) has the
worked example and the metrics endpoint.

## 🧮 GPU split mode

`split-mode` spreads a model over GPUs, and the choice is not free on ROCm.

| Mode     | Placement                      | Best for                          | Costs                                                                                                                                                                           |
| -------- | ------------------------------ | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tensor` | Every layer sliced across GPUs | **Dense** models (fastest decode) | All-reduce per row-parallel projection; silently disables backend (GPU) sampling (dragging `spec-draft-n-max` down) and `llama_params_fit`, so placement must be pinned by hand |
| `layer`  | Whole layers per GPU           | Sparse MoE, uneven topologies     | Slower dense decode; no all-reduce                                                                                                                                              |
| `none`   | Single GPU (`main-gpu`)        | Small models                      | —                                                                                                                                                                               |

> [!WARNING]
> `tensor`'s all-reduce needs RCCL, whose bundled "internal" implementation is CUDA-only. A build missing
> `-DGGML_HIP_RCCL=ON` falls back to a slower meta backend, worth ~20% of the forward pass on `Qwen3.8-27B`. The
> `iommu=pt` and `pcie_aspm=off` kernel parameters matter for the same path ([Installation](installation.md)).

## 💭 Reasoning control

Presets pin `reasoning` explicitly, since `auto` inherits the template default; `Qwen3.5-2B` pins `off` because Open
WebUI drives it as the task model for titles, tags and query rewriting, which must never think.

Per-request switches, in order of preference:

| Switch                                                       | Behavior                                                                                                                                                                                                                                          |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `chat_template_kwargs: { "enable_thinking": true \| false }` | Works both directions regardless of preset; sent by the [harness presets](harnesses.md)                                                                                                                                                           |
| `chat_template_kwargs: { "reasoning_effort": … }`            | Qwen3.8 models take `low`/`medium`/`xhigh` (`high` folds into `xhigh`, unknown values raise). On `Qwen3.8-27B`, `"none"` disables thinking only while `reasoning = auto`; `reasoning = on` ignores it and leaks raw `<think>` tags into `content` |
| `reasoning_budget_tokens: N`                                 | Caps the trace; only `N > 0` is honoured                                                                                                                                                                                                          |

Traces arrive in `message.reasoning_content` (streamed as `delta.reasoning_content`). Large models default
`preserve_thinking` to true, so presets set `reasoning-preserve = off` — prefer that flag over hand-written
`chat-template-kwargs`, which breaks silently if a template renames its variable. It only drops closed-turn traces, so
tool-calling chains retain full reasoning.

**In Open WebUI:** type `none` into _Chat Controls → Advanced Params → reasoning_effort_, or add a Workspace Model
with `chat_template_kwargs: {"enable_thinking": false}`.

## 🌍 Language coverage

Qwen3 models are strongest in English and Chinese and weaker in minor languages — an upstream post-training tradeoff:
quantization, `q8_0` KV cache and the MTP drafter were each measured and none contributes. In heavily inflected
languages greedy output is clean and only _sampled_ choice degrades, each divergence committing the clause to
case/gender/number/aspect agreement. Lower `temp` to `0.6`-`0.7` and add a native-speaker system prompt forbidding
script mixing, per model via a Workspace Model.

---

## ❓ FAQ

### Why does the same preset benchmark differently after a reload?

Each `llama-server` process settles into one of several discrete throughput modes per load. Compare presets with
`--loads 3` (median of per-load medians), never a single load.

### My `tensor-split` looks balanced but one GPU runs out of memory. Why?

The split is by layer count, not bytes, and `n-cpu-moe` empties the leading layers. Count the heavy blocks on each card.

### How do I turn thinking off for one request?

Send `chat_template_kwargs: {"enable_thinking": false}`. It works regardless of the preset's `reasoning` setting.

### Why are answers in my language sometimes ungrammatical?

An upstream training tradeoff that shows under sampling. Lower `temp` to `0.6`-`0.7` and add a native-speaker system
prompt via a Workspace Model.
