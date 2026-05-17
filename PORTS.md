# 🔌 Port Configuration

How Panther Minor exposes services while keeping AI and monitoring endpoints off the public internet.

## 🔐 Security model

> [!IMPORTANT]
> Panther Minor is designed so that **AI and monitoring services are reachable through Tailscale, but blocked from the
> public internet**.

| Layer     | Behavior                                                              |
| --------- | --------------------------------------------------------------------- |
| Docker    | Binds services to `0.0.0.0` inside the host                           |
| UFW       | Blocks service ports from the public internet                         |
| Tailscale | Provides secure access through VPN kernel routing                     |
| Result    | Services stay reachable for trusted clients, but not internet-exposed |

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

| File                 | Responsibility                                |
| -------------------- | --------------------------------------------- |
| `docker-compose.yml` | Service definitions and published ports       |
| `bin/src/bashly.yml` | CLI surface and setup command contract        |
| `bin/src/*.sh`       | Setup logic, firewall rules, and SSH defaults |
