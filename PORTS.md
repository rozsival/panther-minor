# Port Configuration

## Security Model

**UFW blocks public internet → AI/monitoring services accessible via Tailscale VPN only**

- Docker binds to `0.0.0.0` (all interfaces)
- UFW blocks ports from public internet
- Tailscale bypasses UFW via kernel routing
- Result: Services accessible via Tailscale, blocked from internet

## Ports

### Public Internet Access

| Port | Service | Description                   |
|------|---------|-------------------------------|
| 2222 | SSH     | Hardened (key-only, fail2ban) |
| 80   | HTTP    | Future web services           |
| 443  | HTTPS   | Future web services           |

### Tailscale/Local Only

| Port  | Service         | Config Variable     |
|-------|-----------------|---------------------|
| 8000  | Ollama API      | `OLLAMA_PORT`       |
| 8080  | Open WebUI      | `OPEN_WEBUI_PORT`   |
| 3000  | Grafana         | `GRAFANA_PORT`      |
| 9090  | Prometheus      | `PROMETHEUS_PORT`   |
| 5000  | GPU Exporter    | `GPU_EXPORTER_PORT` |
| 9100  | Node Exporter   | Docker network only |
| 11434 | Ollama Metrics  | Docker network only |

## Access

### Via Tailscale (Recommended)

```bash
curl http://panther-minor:8000/v1/models
open http://panther-minor:8080
ssh -p 2222 vit@panther-minor
```

### Via SSH Tunnel

```bash
ssh -p 2222 -L 8080:localhost:8080 vit@<server-ip>
open http://localhost:8080
```

### Direct (On Host)

```bash
curl http://localhost:8000/v1/models
```

## Config Files

- `.env` - port configuration
- `docker-compose.yml` - service definitions
- `scripts/06-ufw.sh` - firewall rules
- `scripts/common.sh` - SSH port



