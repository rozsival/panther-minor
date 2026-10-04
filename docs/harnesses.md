# 👨‍💻 Coding Harnesses

> Ready-made provider configs that connect coding agents — OMP (Oh My Pi), Pi and OpenCode — to Panther Minor's local
> LLM API. Each model is served under one id; thinking and effort are switched per request, and image inputs must stay
> within formats `llama.cpp` can decode.

**Related:** [LLM serving](llm.md#-reasoning-control) · [Models](models.md) · [Networking & security](networking.md)

---

## 📦 Presets

| Harness        | Preset                                                  | Install                                                                                      | Docs                                                                                    |
| -------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| OMP (Oh My Pi) | [`harnesses/omp.yml`](../harnesses/omp.yml)             | `mkdir -p ~/.omp/agent && cp harnesses/omp.yml ~/.omp/agent/models.yml`                      | [omp.sh](https://omp.sh/docs/custom-models)                                             |
| Pi             | [`harnesses/pi.json`](../harnesses/pi.json)             | `mkdir -p ~/.pi/agent && cp harnesses/pi.json ~/.pi/agent/models.json`                       | [pi-mono](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#settings) |
| OpenCode       | [`harnesses/opencode.json`](../harnesses/opencode.json) | `mkdir -p ~/.config/opencode && cp harnesses/opencode.json ~/.config/opencode/opencode.json` | [opencode.ai](https://opencode.ai/docs/config/)                                         |

> [!IMPORTANT]
> Replace `<domain>` in the copied config with your actual domain so the agent reaches the API (`https://<domain>:8000/v1`).

> [!TIP]
> The `harness-config` agent skill (`.agents/skills/harness-config/SKILL.md`) installs or updates these presets for you.

## 🖼️ Images

`llama.cpp` decodes images with `stb_image` (`tools/mtmd/mtmd-helper.cpp`): PNG, JPEG, GIF, BMP, TGA, PSD, HDR, PIC,
PNM — but **not WebP**, which fails with HTTP 400 `Failed to load image or audio file` even on a multimodal model.

| Harness  | WebP behavior                                                                                                                      | Mitigation                                                                                                                               |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| OMP      | Picks the smallest of PNG/JPEG/WebP when re-encoding (screenshots, `read` on images, `eval` output, fetched images), so often WebP | `imageInputDecoder: stb` on each vision model in `omp.yml` (also transcodes WebP already in a resumed session); `OMP_NO_WEBP=1` globally |
| Pi       | Never encodes WebP itself, but passes a WebP **source file** through untouched                                                     | None — avoid `read`ing `.webp` files                                                                                                     |
| OpenCode | Same as Pi                                                                                                                         | None — avoid `read`ing `.webp` files                                                                                                     |

OMP auto-suppresses WebP only for auto-discovered llama.cpp/Ollama/LM Studio providers, which is why the hand-written
`panther-minor` provider declares `imageInputDecoder: stb` explicitly.

## 💭 Thinking

Each model is served under one id and switches reasoning per request via `chat_template_kwargs.enable_thinking` —
there are no separate `-thinking` models to select or reload.

| Harness  | Switch                        | Preset wiring                                                           |
| -------- | ----------------------------- | ----------------------------------------------------------------------- |
| OMP      | Thinking toggle (`Shift+Tab`) | `compat.thinkingFormat: qwen-chat-template`                             |
| Pi       | Thinking toggle               | `compat.chatTemplateKwargs.enable_thinking` bound to `thinking.enabled` |
| OpenCode | Model variant                 | `variants.<name>.chat_template_kwargs`                                  |

OMP also restores per-mode sampling for the Qwen chat models: baseline `extraBody` is the non-thinking sampler,
`whenThinking.extraBody` the thinking one. Pi and OpenCode send no overrides, so both modes fall back to the
thinking-tuned defaults in `llama-cpp/preset.ini`.

### Reasoning effort

The thinking toggle is on/off; how _hard_ a model thinks is a second, model-specific axis:

| Model                | Accepted levels          | Unknown level         |
| -------------------- | ------------------------ | --------------------- |
| `Qwen3.8-27B`        | `low`, `medium`, `xhigh` | template raises → 500 |
| `Qwen3.8-Flash-Next` | `low`, `medium`, `xhigh` | template raises → 500 |
| `Qwen3.6-35B-A3B`    | none — on/off only       | n/a                   |
| `Qwen3.5-2B`         | none — on/off only       | n/a                   |

Each harness constrains the levels per model rather than passing them through:

- **OMP** — `thinking.efforts` owns the ladder and OMP clamps out-of-ladder requests to the nearest member.
  `Qwen3.8-27B`/`Qwen3.8-Flash-Next` declare `efforts: [low, medium, xhigh]` (OMP auto-routes `reasoning_effort` for
  Qwen 3.8+ ids, so no `reasoningEffortMap` is needed) plus `requiresEffort: false`, so `off` sends a real
  `enable_thinking: false` instead of clamping to the lowest effort with thinking still on. `Qwen3.6-35B-A3B`/
  `Qwen3.5-2B` declare a single `efforts: [medium]`, since OMP never routes effort for non-3.8+ ids — one level makes
  the toggle a plain off/on instead of four identical payloads.
- **Pi** — `thinkingLevelMap` maps each level onto a template-accepted string, reaching the template via
  `chatTemplateKwargs.reasoning_effort: { "$var": "thinking.effort" }`. A `null` entry does **not** hide a level — Pi
  clamps it to the nearest mapped one — so both `Qwen3.8-27B` and `Qwen3.8-Flash-Next` map `minimal|low → low`,
  `medium → medium`, `high|xhigh|max → xhigh`.
- **OpenCode** — one named variant per mode, each spelling out **both** kwargs, since variants deep-merge over
  `options` and a variant omitting `reasoning_effort` would otherwise inherit the one from `options`. Auxiliary calls
  (session title, summaries) always use `options` and ignore the selected variant, which is why `options` carries the
  cheapest mode rather than the highest. Select effort with `--variant medium`; `Qwen3.8-27B` and `Qwen3.8-Flash-Next`
  each carry one variant per accepted level.

`Qwen3.8-Flash-Next` defaults `preserve_thinking` to true in its chat template, so the preset sets
`reasoning-preserve = off` to avoid replaying every historical `<think>` block; no template branch forces retention
when tools are present, so no harness needs a tool-call reasoning-content flag.

---

## ❓ FAQ

### My agent gets HTTP 400 "Failed to load image or audio file". Why?

The image is WebP, which `llama.cpp`'s `stb_image` cannot decode. In OMP, keep `imageInputDecoder: stb` on vision
models or set `OMP_NO_WEBP=1`; in Pi and OpenCode, convert `.webp` files before reading them.

### Requests fail with HTTP 500 when I pick a high effort level. Why?

The model's chat template raises on unknown `reasoning_effort` values. Qwen3.8 models accept only `low`, `medium`
and `xhigh`; the presets map other levels onto those.

### Do I need a separate model entry for thinking mode?

No. One id serves both modes; the harness toggles `enable_thinking` per request.

### Why does OpenCode's session title use a different reasoning mode than my chat?

Auxiliary calls always use the model's `options`, which deliberately carry the cheapest mode.

### I added a model to the stack. Do the presets update automatically?

No. Add it to each preset — the `add-model` skill handles `omp.yml`, `pi.json` and `opencode.json` together.
