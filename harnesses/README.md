# 👨‍💻 Coding Harness Presets

Configuration files for connecting external coding agents to Panther Minor's local LLM API.

## Setup

> [!IMPORTANT]
> Replace `<domain>` in the config files with your actual domain so the agent can connect to the API correctly.

- **OMP (Oh My Pi)** — `mkdir -p ~/.omp/agent && cp harnesses/omp.yml ~/.omp/agent/models.yml`
  ([docs](https://omp.sh/docs/custom-models))
- **Pi** — `mkdir -p ~/.pi/agent && cp harnesses/pi.json ~/.pi/agent/models.json`
  ([docs](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#settings))
- **OpenCode** — `mkdir -p ~/.config/opencode && cp harnesses/opencode.json ~/.config/opencode/opencode.json`
  ([docs](https://opencode.ai/docs/config/))

## Images

llama.cpp decodes images with `stb_image` (`tools/mtmd/mtmd-helper.cpp`): PNG, JPEG, GIF, BMP, TGA, PSD, HDR,
PIC, PNM — but **not WebP**, which 400s with `Failed to load image or audio file` even on a multimodal model.

OMP picks the smallest of PNG/JPEG/WebP when it re-encodes images it sends (screenshots, `read` on an image
file, `eval` display output, fetched images), so screenshots often land on WebP; it only auto-suppresses WebP
for auto-discovered llama.cpp/Ollama/LM Studio providers, so a hand-written provider like `panther-minor` must
declare `imageInputDecoder: stb` on each vision model in [`omp.yml`](omp.yml) (this also transcodes WebP
already present in a resumed session) — `OMP_NO_WEBP=1` is the global equivalent for a provider that forgets
the flag. Pi and OpenCode never encode WebP themselves (PNG/JPEG resize ladders and screenshots) but pass a
WebP **source file** through untouched with no switch, so `read`ing a `.webp` from disk still fails there too.

## Thinking

Each model is served under one id and switches reasoning per request via `chat_template_kwargs.enable_thinking`
— there are no separate `-thinking` models to select or reload.

| Harness  | Switch                        | Preset wiring                                                           |
| -------- | ----------------------------- | ----------------------------------------------------------------------- |
| OMP      | thinking toggle (`Shift+Tab`) | `compat.thinkingFormat: qwen-chat-template`                             |
| Pi       | thinking toggle               | `compat.chatTemplateKwargs.enable_thinking` bound to `thinking.enabled` |
| OpenCode | model variant                 | `variants.<name>.chat_template_kwargs`                                  |

OMP also restores per-mode sampling for the Qwen chat models: baseline `extraBody` is the non-thinking sampler,
`whenThinking.extraBody` the thinking one. Pi and OpenCode send no overrides, so both modes fall back to the
thinking-tuned defaults in [`llama-cpp/preset.ini`](../llama-cpp/preset.ini).

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
  `Qwen3.8-27B`/`Qwen3.8-Flash-Next` declare `efforts: [low, medium, xhigh]` (OMP auto-routes
  `reasoning_effort` for Qwen 3.8+ ids, so no `reasoningEffortMap` is needed) plus `requiresEffort: false`, so
  `off` sends a real `enable_thinking: false` instead of clamping to the lowest effort with thinking still on.
  `Qwen3.6-35B-A3B`/`Qwen3.5-2B` declare a single `efforts: [medium]`, since OMP never routes effort for
  non-3.8+ ids — one level makes the toggle a plain off/on instead of four identical payloads.
- **Pi** — `thinkingLevelMap` maps each level onto a template-accepted string, reaching the template via
  `chatTemplateKwargs.reasoning_effort: { "$var": "thinking.effort" }`. A `null` entry does **not** hide a
  level — Pi clamps it to the nearest mapped one — so both `Qwen3.8-27B` and `Qwen3.8-Flash-Next` map
  `minimal|low → low`, `medium → medium`, `high|xhigh|max → xhigh`.
- **OpenCode** — one named variant per mode, each spelling out **both** kwargs, since variants deep-merge over
  `options` and a variant omitting `reasoning_effort` would otherwise inherit the one from `options`; auxiliary
  calls (session title, summaries) always use `options` and ignore the selected variant, which is why
  `options` carries the cheapest mode rather than the highest.

Only OMP and Pi expose effort through the thinking toggle; OpenCode uses a model variant (`--variant medium`),
so `Qwen3.8-27B` and `Qwen3.8-Flash-Next` each carry one variant per accepted level.

`Qwen3.8-Flash-Next` defaults `preserve_thinking` to true in its chat template, so the preset sets
`reasoning-preserve = off` to avoid replaying every historical `<think>` block; no template branch forces
retention when tools are present, so no harness needs a tool-call reasoning-content flag.
