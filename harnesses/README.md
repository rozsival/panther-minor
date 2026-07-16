# 🛠️ Coding Harness Presets

Configuration files for connecting external coding agents to Panther Minor's local LLM API.

## Setup

> [!IMPORTANT]
> Replace `<domain>` in the config files with your actual domain so the agent can connect to the API correctly.

### Pi

Copy the preset files into your Pi agent directory:

```bash
cp harnesses/pi/*.json ~/.pi/agent/
```

See [Pi settings docs](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#settings) for details.

### OpenCode

Copy the preset as your OpenCode configuration:

```bash
cp harnesses/opencode.json ~/.config/opencode/opencode.json
```

See [OpenCode docs](https://opencode.ai/docs/config/) for details.
