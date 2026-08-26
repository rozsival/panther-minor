# 👨‍💻 Coding Harness Presets

Configuration files for connecting external coding agents to Panther Minor's local LLM API.

## Setup

> [!IMPORTANT]
> Replace `<domain>` in the config files with your actual domain so the agent can connect to the API correctly.

### OMP (Oh My Pi)

Copy the models preset into your OMP agent directory:

```bash
mkdir -p ~/.omp/agent
cp harnesses/omp.yml ~/.omp/agent/models.yml
```

See [OMP docs](https://omp.sh/docs/custom-models) for details.

### Pi

Copy the models preset into your Pi agent directory:

```bash
mkdir -p ~/.pi/agent
cp harnesses/pi.json ~/.pi/agent/models.json
```

See [Pi settings docs](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#settings) for details.

### OpenCode

Copy the preset as your OpenCode configuration:

```bash
mkdir -p ~/.config/opencode
cp harnesses/opencode.json ~/.config/opencode/opencode.json
```

See [OpenCode docs](https://opencode.ai/docs/config/) for details.

## Images

llama.cpp decodes image input with `stb_image` (`stbi_load_from_memory` in `tools/mtmd/mtmd-helper.cpp`),
which supports PNG, JPEG, GIF, BMP, TGA, PSD, HDR, PIC and PNM — but **not WebP**. A `data:image/webp`
part is rejected by the server with `400 Failed to load image or audio file`, even though the model itself
is multimodal.

OMP re-encodes every image it sends (screenshots, `read` on an image file, `eval` display output, fetched
images) and keeps the smallest of PNG / JPEG / WebP, so screenshots frequently land on WebP. It suppresses
WebP for servers whose decoder is stb-backed, but only recognises that automatically for auto-discovered
`llama.cpp` / Ollama / LM Studio providers — a hand-written provider like `panther-minor` must declare it,
which is why every vision model in [`omp.yml`](omp.yml) carries `imageInputDecoder: stb`. That flag also
transcodes WebP parts already present in a resumed session. `OMP_NO_WEBP=1` in the environment is the
global equivalent if you add another provider and forget the flag.

Pi and OpenCode never encode WebP — their resize ladders emit PNG and JPEG only, and browser screenshots
are PNG — but both pass a WebP **source file** through untouched and offer no switch, so `read`ing a
`.webp` from disk still fails against llama.cpp on those harnesses.

## Thinking

Each model is served under a single id and switches reasoning per request through
`chat_template_kwargs.enable_thinking` — there are no separate `-thinking` models to select or reload.

| Harness  | How to switch                       | What the preset wires up                                                |
| -------- | ----------------------------------- | ----------------------------------------------------------------------- |
| OMP      | thinking level toggle (`Shift+Tab`) | `compat.thinkingFormat: qwen-chat-template`                             |
| Pi       | thinking level toggle               | `compat.chatTemplateKwargs.enable_thinking` bound to `thinking.enabled` |
| OpenCode | model variant                       | `variants.<name>.chat_template_kwargs`                                  |

The OMP preset also restores the per-mode sampling the old split presets encoded for the Qwen chat models:
the baseline `extraBody` carries the non-thinking sampler, `whenThinking.extraBody` the thinking one. Pi
and OpenCode send no sampling overrides, so both modes use the preset defaults in
[`llama-cpp/preset.ini`](../llama-cpp/preset.ini), which are tuned for thinking.

### Reasoning effort

The thinking toggle is a switch; how _hard_ a model thinks is a second, model-specific axis, and the
models disagree on both the level names and how they fail:

| Model                    | Accepted levels                  | Unknown level         |
| ------------------------ | -------------------------------- | --------------------- |
| `Qwen3.8-27B`            | `low`, `medium`, `xhigh`         | template raises → 500 |
| `DeepSeek-V4-Flash-0731` | `high`, `max` (else no preamble) | silently ignored      |
| `Qwen3.6-35B-A3B`        | none — thinking is on/off only   | n/a                   |
| `Qwen3.5-2B`             | none — thinking is on/off only   | n/a                   |

So each harness needs the levels constrained per model rather than passed through:

- **OMP** — the model-level `thinking` block owns the ladder, `compat.reasoningEffortMap` rewrites
  individual levels, and OMP clamps a request outside the ladder to the nearest member instead of
  sending it:
  - `Qwen3.8-27B` declares `efforts: [low, medium, xhigh]`, so every selectable level is a value the
    template accepts and no selection can 500. A map is the wrong tool here — a mapped value outside
    the ladder is clamped away before it reaches the wire.
  - `Qwen3.6-35B-A3B` and `Qwen3.5-2B` declare `efforts: [medium]`. Effort is never sent for them (OMP
    auto-routes `chat_template_kwargs.reasoning_effort` only for Qwen 3.8+ ids), so a wider ladder
    would be four identical wire payloads; one level makes the toggle a plain off/on.
  - `DeepSeek-V4-Flash-0731` needs `compat.qwenTemplateReasoningEffort: true`, because effort routing
    is auto-detected only for Qwen 3.8+ ids; without it the level is never sent and the model always
    runs at the preset default. Its ladder is owned by OMP's built-in DeepSeek policy and cannot be
    replaced, so the map carries the three template modes: `low → none`, `medium → high`, `xhigh → max`.
  - Both `Qwen3.8-27B` and `DeepSeek-V4-Flash-0731` also set `requiresEffort: false`; OMP otherwise
    treats their effort as mandatory and turns `off` into the lowest effort with thinking still on
    instead of `enable_thinking: false`.
- **Pi** — model-level `thinkingLevelMap` maps each level onto a template-accepted string and the effort
  reaches the template through `chatTemplateKwargs.reasoning_effort: { "$var": "thinking.effort" }`. A
  `null` entry does **not** hide the level: Pi clamps it to the nearest mapped one, so every level must
  land on something the template accepts. `Qwen3.8-27B` therefore maps `minimal|low → low`,
  `medium → medium` and `high|xhigh|max → xhigh`; DeepSeek maps `low → none` (plain thinking),
  `high → high` and `max → max`, with the nulls in between clamping onto those three.
- **OpenCode** — one named variant per mode, each spelling out **both** kwargs. Variants deep-merge over
  `options`, so a variant that omits `reasoning_effort` inherits the one from `options` — DeepSeek's
  `none` variant has to say `reasoning_effort: "none"` explicitly or "no thinking" ships
  `enable_thinking: false` next to a stale `high`. OpenCode's auxiliary calls (session title, summaries)
  always use `options` and ignore the selected variant, which is why `options` carries the cheapest
  mode rather than `high`.

Only OMP and Pi expose the effort axis through the thinking toggle; in OpenCode it is a model variant
(`--variant medium`), so `Qwen3.8-27B` carries one variant per accepted level.

DeepSeek-V4 keeps the reasoning of **every** assistant turn once tools are present — that branch of the
template is hardcoded and ignores `reasoning-preserve`. It also always opens a `<think>` block for those
turns, so OMP sets `requiresReasoningContentForToolCalls: true` to avoid replaying empty ones. Long
agentic sessions grow faster than the Qwen models as a result.
