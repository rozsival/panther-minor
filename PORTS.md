# 🔌 Port Configuration

How Panther Minor exposes services while keeping AI and monitoring endpoints off the public internet.

## 🔐 Security model

> [!IMPORTANT]
> Panther Minor is designed so that **AI and monitoring services are reachable through Tailscale, but blocked from the
> public internet**.

| Layer     | Behavior                                                                                                |
| --------- | ------------------------------------------------------------------------------------------------------- |
| Docker    | Publishes the proxy's ports on `127.0.0.1` and `BIND_ADDR` (this node's Tailscale IP) — never `0.0.0.0` |
| UFW       | Blocks host-local service ports on the `INPUT` path                                                     |
| Tailscale | Provides secure access through VPN kernel routing                                                       |
| Result    | Services stay reachable for trusted clients, but not internet-exposed                                   |

> [!NOTE]
> Why the bind address, not a firewall rule: Docker publishes ports with `nat/PREROUTING`
> DNAT, so packets reaching a container are _forwarded_, not delivered locally — they
> never traverse the `INPUT` chain UFW manages, and `ufw deny 8000` cannot block a
> published port (moby/moby#17496). A published port scoped to an address is enforced by
> the DNAT rule itself, so the exposure does not exist in the first place.
>
> `proxy` is the only service that publishes ports; everything else uses `expose:` and is
> reachable only inside the `ai` network. `BIND_ADDR` is mandatory: unset, the stack
> refuses to start rather than silently falling back to `0.0.0.0`. `setup env` fills it
> from `tailscale ip -4` — re-run `sudo ./bin/cli setup env` after `sudo tailscale up`.
>
> Consequence worth knowing: `cluster start` requires Tailscale to be up, because the
> proxy cannot bind an address that does not exist yet. That is the intended failure
> direction — a broken tunnel stops the stack instead of exposing it.

## 🌐 Port exposure

### Public internet access

Only the entrypoint ports required for secure host and web access should be internet reachable.

| Port   | Service | Purpose                      |
| ------ | ------- | ---------------------------- |
| `2222` | SSH     | Hardened remote shell access |
| `80`   | HTTP    | ACME / web entrypoint        |
| `443`  | HTTPS   | Secure service access        |

### Tailscale / local-only services

These services are intended for Tailscale clients or direct host access.

| Port   | Service         | Role                                               |
| ------ | --------------- | -------------------------------------------------- |
| `8000` | `llama-manager` | OpenAI-compatible proxy and activity-aware routing |
| `8001` | `sd-manager`    | OpenAI-compatible image generation API             |
| `8080` | `open-webui`    | Browser UI for chatting with models                |
| `3000` | `grafana`       | Dashboards and visualization                       |
| `9090` | `prometheus`    | Metrics scraping and storage                       |

## 🚪 Access patterns

### Via Tailscale (recommended)

Use this for normal remote access.

```bash
curl https://<domain>:8000/v1/models
open https://<domain>:8080
ssh -p 2222 <user>@<server-name>
```

### Via SSH tunnel

Use this when you need a secure local tunnel to a single service.

```bash
ssh -p 2222 -L 8080:localhost:8080 <user>@<server-ip>
open https://localhost:8080
```

### Directly on the host

Useful for local diagnostics on the server itself.

```bash
curl -k https://localhost:8000/v1/models
```

## 🛠️ Where port behavior is defined

| File                 | Responsibility                                                    |
| -------------------- | ----------------------------------------------------------------- |
| `docker-compose.yml` | Service definitions and address-scoped published ports            |
| `.env`               | `BIND_ADDR` — the address published ports are scoped to           |
| `bin/src/bashly.yml` | CLI surface and setup command contract                            |
| `bin/src/*.sh`       | Setup logic, `BIND_ADDR` resolution, firewall rules, SSH defaults |
