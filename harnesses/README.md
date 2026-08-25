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

The thinking toggle is a switch; how _hard_ a model thinks is a second, model-specific axis, and the two
chat models disagree on both the level names and how they fail:

| Model                    | Accepted levels                  | Unknown level         |
| ------------------------ | -------------------------------- | --------------------- |
| `Qwen3.8-27B`            | `low`, `medium`, `xhigh`         | template raises → 500 |
| `DeepSeek-V4-Flash-0731` | `high`, `max` (else no preamble) | silently ignored      |

So each harness needs the levels remapped per model rather than passed through:

- **OMP** — `compat.reasoningEffortMap` rewrites the offending levels. DeepSeek also needs
  `compat.qwenTemplateReasoningEffort: true`, because OMP only auto-routes effort onto
  `chat_template_kwargs.reasoning_effort` for Qwen 3.8+ ids; without it the level is never sent and the
  model always runs at the preset default.
- **Pi** — model-level `thinkingLevelMap` maps the levels it supports and uses `null` to hide the rest,
  so DeepSeek exposes only off / `high` / `max` in the UI. The effort value reaches the template through
  `chatTemplateKwargs.reasoning_effort: { "$var": "thinking.effort" }`.
- **OpenCode** — one named variant per mode (`none`, `thinking`, `high`, `max` for DeepSeek), each
  spelling out both kwargs so the result does not depend on how variants merge over `options`.

DeepSeek-V4 keeps the reasoning of **every** assistant turn once tools are present — that branch of the
template is hardcoded and ignores `reasoning-preserve`. It also always opens a `<think>` block for those
turns, so OMP sets `requiresReasoningContentForToolCalls: true` to avoid replaying empty ones. Long
agentic sessions grow faster than the Qwen models as a result.
