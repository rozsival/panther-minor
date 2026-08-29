---
name: tune-preset
description: >
  Tune a llama.cpp preset in `llama-cpp/preset.ini` — VRAM placement (`n-gpu-layers`, `n-cpu-moe`,
  `tensor-split`, `load-mode`), speculative-decoding depth (`spec-draft-n-max`), and `split-mode` —
  through measured, one-knob-at-a-time benchmarking. Use when the user says "tune the preset", "model
  is OOMing", "speed up decode", "adjust n-cpu-moe / tensor-split / spec-draft-n-max", "benchmark a
  model", or "why is this model slow".
---

You are tuning a `llama-cpp/preset.ini` section for measured throughput, not guesswork. Every claim in
this skill traces back to a real preset in this repo — read the target section before touching it, and
read `models/README.md` for the worked example (`Qwen3.8-Flash-Next`) if you need the full derivation
behind any number.

## Measurement-first loop — never skip a step

1. **Baseline before changing anything**:
   ```bash
   ./bin/cli models llm bench <preset>
   ```
   This pins every variable that would otherwise drift: a fixed 24-sentence prompt, `seed = 42`,
   `temperature = 0` (greedy), `cache_prompt = false` (prefill is measured, not replayed from the slot
   cache), and `ignore_eos = true` (exactly `--tokens` are predicted, default 256, 3 runs + 1 discarded
   warm-up, median of the runs). Each line appended to `models/bench.log` also carries the host kernel
   (`uname -r`), the llama.cpp commit inside the container, and the image ID — so a later regression is
   attributable to one of those four things moving, not a guess.
2. **Change exactly ONE knob.** Never combine `n-cpu-moe` + `tensor-split` + `spec-draft-n-max` in one
   edit — if throughput moves you won't know which change did it, and if it OOMs you won't know which
   change to revert.
3. **Reload weights, then re-bench**:
   ```bash
   ./bin/cli models llm unload <preset>
   ./bin/cli models llm load <preset>
   ./bin/cli models llm bench <preset>
   ```
   Presets map 1:1 to models — `load`/`unload` take the **preset** name from `llama-cpp/preset.ini`,
   `download`/`remove` take the **model** name from `models/llm.config.json`. Reasoning mode
   (`chat_template_kwargs.enable_thinking`, `reasoning_effort`) is a per-request switch, not a preset
   field — never reload weights just to change it.
4. **Keep or revert.** Compare the new `models/bench.log` line against the previous one for that preset
   (decode tok/s, prefill tok/s, draft acceptance). If it regressed or only moved within noise, edit
   `llama-cpp/preset.ini` back and re-bench to confirm the revert lands where the baseline was.

> [!WARNING]
> A bench run that used `cache_prompt`-warm state or a different `--tokens`/`--runs` value is not
> comparable to the baseline. Keep the invocation identical (or pass matching `--tokens`/`--runs`
> explicitly) across every iteration you intend to compare.

## The knobs

### `tensor-split` — splits by LAYER INDEX, not by bytes

`llama-model.cpp` assigns layer `il` to a device by comparing `il / (n_layer + 1)` against the
normalized split — it has no idea how heavy any given layer is. Combined with `n-cpu-moe` (below),
which makes the first N layers nearly weightless, a split that looks balanced on paper is not balanced
in VRAM. **Count the heavy blocks landing on each side, not the layer count.**

Failure signature to recognize immediately:

```
cudaMalloc failed: out of memory
```

That's what a byte-balanced-looking split produces the moment one card gets more heavy blocks than it
can hold — `52,48` on `Qwen3.8-Flash-Next` handed GPU 1 twenty-two heavy layers plus the output head (a
single 35.35 GiB allocation on a 31.86 GiB card) and OOMed; `72,28` fixed it by putting the light,
`n-cpu-moe`'d layers 0-35 on GPU 0 and only layers 36-47 plus the output head on GPU 1.

Also account for **always-resident small models** before claiming headroom on a card: any preset with
`main-gpu = 1` (`Qwen3-Embedding-0.6B`, `Qwen3.5-2B` in this repo) stays loaded regardless of what large
model is active, because the manager only arbitrates _large_ models. Budget ~6 GiB per pinned small
model on whichever GPU they target.

### `n-cpu-moe = N` — moves routed experts to host RAM

Moves the first N transformer blocks' routed-expert weights off the GPU and into system RAM. Cheap per
token — only `expert_used_count` of `expert_count` experts are actually read for any given token — but
every one of those reads is now a PCIe round trip, and offloading blocks disables llama.cpp's multi-GPU
pipeline parallelism. Raise N only as far as the VRAM budget forces you to; each increment trades a
fixed amount of freed VRAM for a per-token PCIe cost you can read directly off the bench log's decode
tok/s delta.

### `load-mode = none` vs mmap

Default is mmap. For a large CPU-resident tensor set (host-side MoE overrides, huge embedding tables),
llama.cpp warns that `mmap`'d CPU tensor overrides are slower than reading them straight into memory —
set `load-mode = none` when the host has enough free RAM to hold the resident set without page-cache
pressure. Check free RAM before flipping this; it front-loads the read at load time instead of
amortizing page faults across the first few requests.

### `split-mode` — not free on ROCm

- **`tensor`** — every GPU holds a slice of every layer; the per-GPU weight stream is divided by GPU
  count. Fastest for **dense** models (bandwidth-bound decode) — this is what `Qwen3.8-27B` uses. Needs
  an all-reduce after every row-parallel projection, which needs RCCL (`-DGGML_HIP_RCCL=ON` at build
  time); without it every reduction falls back to a slow generic path. It also **disables**:
  - **Backend (GPU) sampling** — `llama_set_sampler` refuses under `SPLIT_MODE_TENSOR`, so every draft
    and verify position ships a full logit vector over PCIe on the CPU instead. This raises per-draft-
    token cost and pulls the best `spec-draft-n-max` down.
  - **`llama_params_fit`** — automatic placement is unavailable; `n-gpu-layers`, `n-cpu-moe`, and
    `tensor-split` must be pinned by hand.
- **`layer`** — whole layers per GPU, no all-reduce, but a single request streams the full weights
  through one GPU at a time (slower dense decode). Suits sparse MoE models and uneven topologies,
  optionally combined with `tensor-split`. Used by `Qwen3.6-35B-A3B` and `Qwen3.8-Flash-Next`.
- **`none`** — single GPU, paired with `main-gpu`. Used by the small always-resident models.

### `spec-draft-n-max` — draft depth

How many tokens the drafter proposes per round. Acceptance decays geometrically, so the optimum is
where the marginal accepted token stops paying for its draft-and-sample cycle — not the largest depth
the checkpoint allows, and not a value you can pick from spec sheets. Measure it:

- `llama-server` logs `draft acceptance = <rate> (<accepted>/<generated>), mean len = <n>` per request.
- Per-position falloff:
  ```bash
  curl -s localhost:8000/metrics | grep spec_decode_num_accepted_tokens_per_pos_total
  ```
- **Benchmark at production sampling.** `./bin/cli models llm bench` runs greedy (`temperature = 0`),
  which inflates acceptance and pushes the apparent optimum higher than it is at the preset's real
  `temp`/`top-k`/`top-p`. Cross-check with a manual request at the preset's actual sampler settings
  before committing a depth change, and note in the commit which sampler you measured at.

Depth 2 is the current value on every speculating preset in this repo (`Qwen3.8-27B`,
`Qwen3.6-35B-A3B`, `Qwen3.5-2B` all run `spec-draft-n-max = 2`); depths 3-4 have been measured slower
than no speculation at all on this hardware. Treat any depth as a hypothesis to re-measure, not a
constant — acceptance is workload- and sampler-dependent.

## Log lines that mean something

| Line                                                                                       | Meaning                                                                                                                                                                                                              |
| ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cudaMalloc failed: out of memory`                                                         | `tensor-split`/`n-cpu-moe`/`n-gpu-layers` placement put too many heavy blocks on one card — recount heavy blocks per side, don't rebalance by layer count.                                                           |
| `internal AllReduce init failed (n_devices != 2?); falling back to meta-backend butterfly` | RCCL is not compiled in or not linked for this `split-mode = tensor` preset; the all-reduce fell back to a slow generic path. The `n_devices` wording is misleading on ROCm — check the build, not the device count. |
| `backend sampling not supported with SPLIT_MODE_TENSOR`                                    | Expected under `split-mode = tensor` — sampling runs on CPU, which raises per-draft-token cost and should pull `spec-draft-n-max` down. Not a bug to fix.                                                            |
| `backend offload failed for seq_id=`                                                       | Same `split-mode = tensor` limitation as above, seen alongside the CPU-sampling warning.                                                                                                                             |
| `draft acceptance = <rate> (<accepted>/<generated>), mean len = <n>`                       | Per-request speculative-decoding acceptance — the primary signal for tuning `spec-draft-n-max`.                                                                                                                      |

## Inspecting live state

```bash
./bin/cli logs llama-cpp --tail 200   # one-time snapshot of the llama.cpp container's recent logs
./bin/cli logs llama-cpp              # stream logs live (no --tail)
curl -s localhost:8000/status         # llama-manager: current load state, in-flight counts, idle timers
curl -s localhost:8000/metrics        # llama.cpp server: Prometheus metrics, incl. spec_decode_* series
```

## Committing a tuned value

Once a change is kept (bench log shows a real, repeatable delta):

- Commit message is Conventional Commits, lowercase, no final period, ≤100 chars — `perf(llama-cpp): …`
  for a throughput/placement win, `fix(llama-cpp): …` for a correctness fix (e.g. an OOM avoided).
  Examples from this repo's history: `perf(llama-cpp): tune deepseek spec decoding`,
  `fix(llama-cpp): reduce spec-draft-n-max`, `perf(llama-cpp): use tensor split`.
- If the tuned number is one `models/README.md` documents (VRAM budget, measured tok/s, split
  rationale, draft depth), update that doc in the same change — it is the narrative explanation of
  numbers that live in `llama-cpp/preset.ini`, and a stale doc is worse than no doc. Do not edit
  `models/README.md` for changes that don't touch a number it states.
