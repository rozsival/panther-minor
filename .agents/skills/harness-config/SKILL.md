---
name: harness-config
description: >
  Install or update a local coding-harness config (OMP, Pi, or OpenCode) from this repo's presets in
  `harnesses/`, wiring it to the Panther Minor llama.cpp server. Use when the user says "set up my coding
  harness", "install the OMP/Pi/OpenCode config", "update my harness config", "point my agent at the
  llama server", or "configure OMP models".
---

You are wiring a local coding harness (OMP, Pi, and/or OpenCode) to this stack's `panther-minor` OpenAI-
compatible provider. Work through the steps in order. Never guess a harness or a tailnet — ask or detect.

## 1. Autodetect

Check all three harnesses, both the binary and the config path:

| Harness  | Binary check          | Config file                        |
| -------- | --------------------- | ---------------------------------- |
| OMP      | `command -v omp`      | `~/.omp/agent/models.yml`          |
| Pi       | `command -v pi`       | `~/.pi/agent/models.json`          |
| OpenCode | `command -v opencode` | `~/.config/opencode/opencode.json` |

Run:

```bash
command -v omp; test -f ~/.omp/agent/models.yml && echo "omp config: present"
command -v pi; test -f ~/.pi/agent/models.json && echo "pi config: present"
command -v opencode; test -f ~/.config/opencode/opencode.json && echo "opencode config: present"
```

A harness counts as "present" if the binary is found **or** its config file exists (the binary may be a
wrapper installed elsewhere, or the config may predate a reinstalled binary).

- **Exactly one present** → proceed with that harness.
- **More than one present** → ask the user which to configure (use an ask/choice tool if available,
  otherwise plain chat), offering each detected harness individually plus an "all detected" option.
- **None present** → tell the user no supported harness was detected, and ask whether to install a config
  anyway for a named harness (OMP, Pi, or OpenCode). Never silently pick one.

If multiple harnesses are selected (including "all detected"), process them **sequentially**, one full
pass of steps 2–4 per harness, and report each result separately in step 5.

## 2. Resolve the host

Clients reach the stack through the Tailscale sidecar node `panther`, so the base URL is
`https://panther.<tailnet>.ts.net:8000/v1`. The preset files carry exactly that, with `<tailnet>` as the
placeholder (`baseUrl` in `harnesses/omp.yml` and `harnesses/pi.json`,
`provider.panther-minor.options.baseURL` in `harnesses/opencode.json`).

**Fresh install (no existing config for this harness):** detect the tailnet from the local Tailscale client:

```bash
tailscale status --json | jq -r '.MagicDNSSuffix'   # e.g. tail1234.ts.net
```

On macOS the CLI may only exist inside the app bundle: `/Applications/Tailscale.app/Contents/MacOS/Tailscale`.
If detection fails (no Tailscale on this machine, not logged in), ask the user for the tailnet DNS name or the
full host. Accept any of these forms and normalize:

| Input                                               | Resolved base URL                         |
| --------------------------------------------------- | ----------------------------------------- |
| `tail1234.ts.net` (detected suffix or tailnet name) | `https://panther.tail1234.ts.net:8000/v1` |
| `panther.tail1234.ts.net` (full host)               | `https://panther.tail1234.ts.net:8000/v1` |
| `https://other.host:9443/v1` (full URL)             | used verbatim (append `/v1` if missing)   |

Only default the node to `panther`, the port to `8000` and the scheme to `https` when the user did **not**
supply their own.

**Update (config already exists):** extract the host already installed — grep the provider's URL line out of
the installed file:

```bash
grep -oE '"?base[Uu][Rr][Ll]"?: *"?https?://[^"'"'"':/]+(:[0-9]+)?' <installed-file>
```

(For OMP's YAML this is the `baseUrl:` line under `providers.panther-minor`; for Pi it's `baseUrl` under
the same path; for OpenCode it's `baseURL` under `provider.panther-minor.options`.)

- If the value is a real `*.ts.net` host (no `<tailnet>` placeholder), reuse it without asking.
- If it is any other host, it predates the Tailscale sidecar (the old own-domain URL, which no longer
  answers): tell the user, then resolve the host as in the fresh-install case. Never carry the old host over.
- If extraction fails, or the value still contains a placeholder (`<tailnet>`, or the older `<domain>`),
  resolve as in the fresh-install case.

Before writing anything, state the resolved base URL back to the user (e.g. "Using
`https://panther.tail1234.ts.net:8000/v1`").

## 3. Install or update

### Fresh install

```bash
mkdir -p ~/.omp/agent            # OMP
mkdir -p ~/.pi/agent             # Pi
mkdir -p ~/.config/opencode      # OpenCode
```

Copy the matching preset over the target path, then replace the literal `<tailnet>.ts.net` with the
resolved tailnet suffix (the presets only place it inside an existing `https://panther.<tailnet>.ts.net:8000/v1`
skeleton, so substitute just that segment unless the user supplied their own host or URL, in which case
replace the whole base URL with the resolved one):

```bash
cp harnesses/omp.yml ~/.omp/agent/models.yml
cp harnesses/pi.json ~/.pi/agent/models.json
cp harnesses/opencode.json ~/.config/opencode/opencode.json
```

Then edit the copied file (never the preset in this repo) to substitute the host.

### Update

The installed file may carry user-local edits — other providers, extra models, unrelated settings. Never
blind-overwrite it. Diff the installed file against this repo's preset first:

```bash
diff -u ~/.omp/agent/models.yml harnesses/omp.yml
diff -u ~/.pi/agent/models.json harnesses/pi.json
diff -u ~/.config/opencode/opencode.json harnesses/opencode.json
```

Show the user the meaningful differences (ignore the host-only diff line). Then replace **only** the
`panther-minor` provider block and the models it owns with the preset's version (re-applying the resolved
host), leaving every other provider, model, and setting in the installed file untouched. Read the
installed file structurally and use a targeted edit — do not regex-splice a whole-file replace.

> [!IMPORTANT]
> `~/.config/opencode/opencode.json` is the user's **entire** OpenCode configuration, not a
> harness-specific file like OMP's or Pi's. Merging carefully here matters more: preserve every other top-
> level key (`$schema`, other `provider` entries, `agent`, `mcp`, etc.) and only touch
> `provider.panther-minor`.

## 4. Verify

1. **Parses.** For the two JSON targets:
   ```bash
   node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); console.log('ok')" ~/.pi/agent/models.json
   node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); console.log('ok')" ~/.config/opencode/opencode.json
   ```
   For OMP's YAML, prefer a real parser if one is available on the machine:
   ```bash
   python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1])); print('ok')" ~/.omp/agent/models.yml
   # or, if PyYAML isn't installed but yq is:
   yq e . ~/.omp/agent/models.yml >/dev/null && echo ok
   ```
   If neither is available, re-read the written file carefully (structure, indentation, colons) and
   confirm it is well-formed YAML by inspection.
2. **No placeholder left.**
   ```bash
   grep -rnE '<tailnet>|<domain>' ~/.omp/agent/models.yml ~/.pi/agent/models.json ~/.config/opencode/opencode.json
   ```
   This must return nothing for any file you touched.
3. **Connectivity smoke test.**
   ```bash
   curl -s https://panther.<resolved-tailnet>.ts.net:8000/v1/models
   ```
   Report the model ids returned. If `curl` fails (timeout, connection refused, DNS failure, TLS error),
   report it as a **reachability problem, not a config error** — leave the written config in place; the
   server may be off, this machine may not be on the tailnet, or the tailnet policy may not grant it access
   to `tag:panther`.

## 5. Report

For each harness configured, report:

- The exact file path written (and whether it was a fresh install or an update).
- The resolved host / base URL used.
- How the user switches thinking and effort in that harness, sourced from `docs/harnesses.md`:
  - **OMP** — thinking level toggle (`Shift+Tab`); effort ladder is per-model (`low`/`medium`/`xhigh` for
    `Qwen3.8-27B` and `Qwen3.8-Flash-Next`, single `medium` level — plain on/off — for
    `Qwen3.6-35B-A3B` and `Qwen3.5-2B`).
  - **Pi** — thinking level toggle, mapped per model onto the levels the chat template accepts
    (`minimal|low → low`, `medium → medium`, `high|xhigh|max → xhigh` for the two models with an effort
    ladder; plain on/off for the other two).
  - **OpenCode** — pick a model variant (e.g. `--variant medium`); `Qwen3.8-27B` and
    `Qwen3.8-Flash-Next` carry `none`/`thinking`/`medium`/`xhigh`, while `Qwen3.6-35B-A3B` and
    `Qwen3.5-2B` carry only `none`/`thinking` (no effort ladder).

## Error handling

- **Binary present, config dir missing.** Not an error — `mkdir -p` the directory as part of the fresh
  install and continue.
- **Existing config is invalid JSON/YAML.** Before touching it, back it up:
  ```bash
  cp ~/.pi/agent/models.json ~/.pi/agent/models.json.bak
  ```
  (same pattern for the OMP and OpenCode paths). Tell the user the original was invalid, that a `.bak`
  copy was made, and then proceed as a fresh install (the merge step has nothing valid to diff against).
- **Multiple harnesses selected.** Process them sequentially — finish steps 2–4 for one harness before
  starting the next — and report each in its own bullet under step 5. A failure in one harness (e.g. its
  curl smoke test fails) must not block or skip the others.
