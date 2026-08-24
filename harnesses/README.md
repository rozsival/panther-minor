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
