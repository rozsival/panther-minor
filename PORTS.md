# Port Configuration

## Security Model

**UFW blocks public internet → AI/monitoring services accessible via Tailscale VPN only**

- Docker binds to `0.0.0.0` (all interfaces)
- UFW blocks ports from public internet
- Tailscale bypasses UFW via kernel routing
- Result: Services accessible via Tailscale, blocked from internet

## Ports

### Public Internet Access

| Port | Service |
| ---- | ------- |
| 2222 | SSH     |
| 80   | HTTP    |
| 443  | HTTPS   |

### Tailscale/Local Only

| Port | Service       |
| ---- | ------------- |
| 8000 | llama.cpp API |
| 8080 | Open WebUI    |
| 3000 | Grafana       |
| 9090 | Prometheus    |

## Access

### Via Tailscale (Recommended)

```bash
curl https://panther.vitrozsival.cz:11434/v1/models
open https://panther.vitrozsival.cz:8080
ssh -p 2222 vit@panther-minor
```

### Via SSH Tunnel

```bash
ssh -p 2222 -L 8080:localhost:8080 vit@<server-ip>
open http://localhost:8080
```

### Direct (On Host)

```bash
curl http://localhost:11434/v1/models
```

## Config Files

- `docker-compose.yml` - service definitions
- `scripts/06-ufw.sh` - firewall rules
- `scripts/common.sh` - SSH port
