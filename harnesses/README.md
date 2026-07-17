# 👨‍💻 Coding Harness Presets

Configuration files for connecting external coding agents to Panther Minor's local LLM API.

## Setup

> [!IMPORTANT]
> Replace `<domain>` in the config files with your actual domain so the agent can connect to the API correctly.

### OMP (Oh My Pi)

Copy the preset files into your OMP agent directory:

```bash
mkdir -p ~/.omp/agent
cp harnesses/omp/*.yml ~/.omp/agent/
```

See [OMP docs](https://omp.sh/docs/custom-models) for details.

### Pi

Copy the preset files into your Pi agent directory:

```bash
mkdir -p ~/.pi/agent
cp harnesses/pi/*.json ~/.pi/agent/
```

See [Pi settings docs](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#settings) for details.

### OpenCode

Copy the preset as your OpenCode configuration:

```bash
mkdir -p ~/.config/opencode
cp harnesses/opencode.json ~/.config/opencode/opencode.json
```

See [OpenCode docs](https://opencode.ai/docs/config/) for details.
