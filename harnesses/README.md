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
| OpenCode | model variant `thinking` / `none`   | `variants.<name>.chat_template_kwargs`                                  |

The OMP preset also restores the per-mode sampling the old split presets encoded for the Qwen3.6 models:
the baseline `extraBody` carries the non-thinking sampler, `whenThinking.extraBody` the thinking one. Pi
and OpenCode send no sampling overrides, so both modes use the preset defaults in
[`llama-cpp/preset.ini`](../llama-cpp/preset.ini), which are tuned for thinking.
