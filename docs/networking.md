# 🔌 Networking & Security

> AI and monitoring services are reachable through Tailscale and loopback, never from the public internet. The
> guarantee comes from binding published ports to `127.0.0.1` and the node's Tailscale address (`BIND_ADDR`), not
> from firewall rules.

**Related:** [Installation](installation.md) · [Architecture](architecture.md) · [Operations](operations.md)

---

## 🔐 Security model

| Layer     | Behavior                                                                                                |
| --------- | ------------------------------------------------------------------------------------------------------- |
| Docker    | Publishes the proxy's ports on `127.0.0.1` and `BIND_ADDR` (this node's Tailscale IP) — never `0.0.0.0` |
| UFW       | Allows only `2222`, `80` and `443` on the `INPUT` path                                                  |
| fail2ban  | Bans brute-force attempts on the SSH port                                                               |
| SSH       | Port `2222`, key-only authentication, `AllowUsers` restricted                                           |
| Tailscale | Provides the private network trusted clients connect through                                            |
| Result    | Services stay reachable for trusted clients, but are not internet-exposed                               |

### Why the bind address, not a firewall rule

Docker publishes ports with `nat/PREROUTING` DNAT, so packets reaching a container are _forwarded_, not delivered
locally — they never traverse the `INPUT` chain UFW manages, and `ufw deny 8000` cannot block a published port
([moby/moby#17496](https://github.com/moby/moby/issues/17496)). A published port scoped to an address is enforced by
the DNAT rule itself, so the exposure does not exist in the first place.

`proxy` is the only service that publishes ports; everything else uses `expose:` and is reachable only inside the
`ai` Docker network.

> [!IMPORTANT]
> `BIND_ADDR` is **mandatory**. Unset, the stack refuses to start rather than silently falling back to `0.0.0.0`.
> `setup env` fills it from `tailscale ip -4` — re-run `sudo ./bin/panther-minor setup env` after `sudo tailscale up`.
>
> Consequence: `cluster start` requires Tailscale to be up, because the proxy cannot bind an address that does not
> exist yet. That is the intended failure direction — a broken tunnel stops the stack instead of exposing it.

## 🌐 Port reference

### Public internet

Only the entrypoints required for host access and certificate issuance are open in UFW.

| Port   | Service | Purpose                      |
| ------ | ------- | ---------------------------- |
| `2222` | SSH     | Hardened remote shell access |
| `80`   | HTTP    | ACME / web entrypoint        |
| `443`  | HTTPS   | Secure service access        |

### Tailscale and loopback only

Published by `proxy` on `127.0.0.1` and `BIND_ADDR`, all over TLS.

| Port   | Upstream        | Role                                                    |
| ------ | --------------- | ------------------------------------------------------- |
| `8000` | `llama-manager` | OpenAI-compatible LLM API with activity-aware routing   |
| `8001` | `sd-manager`    | OpenAI-compatible image generation API                  |
| `8080` | `open-webui`    | Browser UI for chat and image generation                |
| `3000` | `grafana`       | Dashboards and visualization                            |
| `9090` | `prometheus`    | Metrics scraping and storage                            |
| `4200` | —               | Published by `proxy`; no listener in `proxy/nginx.conf` |

### Internal only

Reachable solely inside the `ai` network: `llama-cpp` and `stable-diffusion-cpp` (`8000`), `amd-gpu-exporter`
(`5000`), `node-exporter` (`9100`), `llama-metrics-exporter` and `sd-metrics-exporter` (`9090`).

## 🚪 Access patterns

### Via Tailscale (recommended)

```bash
curl https://<domain>:8000/v1/models
open https://<domain>:8080
ssh -p 2222 <user>@<server-name>
```

### Via SSH tunnel

For a single service when Tailscale is not available on the client:

```bash
ssh -p 2222 -L 8080:localhost:8080 <user>@<server-ip>
open https://localhost:8080
```

### Directly on the host

For local diagnostics on the server itself:

```bash
curl -k https://localhost:8000/v1/models
```

## 🛠️ Where network behavior is defined

| File                 | Responsibility                                                    |
| -------------------- | ----------------------------------------------------------------- |
| `docker-compose.yml` | Service definitions and address-scoped published ports            |
| `proxy/nginx.conf`   | TLS listeners and upstream routing per port                       |
| `.env`               | `BIND_ADDR` — the address published ports are scoped to           |
| `cli/bashly.yml`     | CLI surface and setup command contract                            |
| `cli/**/*.sh`        | Setup logic, `BIND_ADDR` resolution, firewall rules, SSH defaults |

---

## ❓ FAQ

### Why can't I just `ufw deny` a port?

Because Docker's DNAT forwards published-port traffic around the `INPUT` chain, so UFW never sees it. Address-scoped
publishing is the only reliable control.

### The cluster won't start after a reboot. Is Tailscale down?

Likely. If the Tailscale address does not exist, the proxy cannot bind `BIND_ADDR` and the stack stays down by
design. Bring Tailscale up, then `./bin/panther-minor cluster start`.

### My Tailscale IP changed. What now?

Re-run `sudo ./bin/panther-minor setup env` to refresh `BIND_ADDR`, then restart the cluster.

### Can other devices on my LAN reach the services?

No. Ports are published only on loopback and the Tailscale address; LAN clients must join the tailnet or use an SSH
tunnel.
