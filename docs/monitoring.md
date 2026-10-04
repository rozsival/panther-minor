# 📈 Monitoring

> Prometheus scrapes four exporters every 15 seconds and keeps 30 days of history; Grafana ships four provisioned
> dashboards for the GPUs, the host, `llama.cpp` and `stable-diffusion.cpp`. The inference exporters are
> activity-aware, so monitoring never wakes an idle model.

**Related:** [GPU power & VRAM](gpu-management.md) · [Architecture](architecture.md) ·
[Networking & security](networking.md) · [LLM serving](llm.md)

---

## 🧭 Access

| UI         | URL                     | Auth                                   |
| ---------- | ----------------------- | -------------------------------------- |
| Grafana    | `https://<domain>:3000` | Anonymous `Admin`, login form disabled |
| Prometheus | `https://<domain>:9090` | None (lifecycle API enabled)           |

Both are reachable only via Tailscale or loopback — see [Networking & security](networking.md).

## 🎯 Scrape targets

Defined in `monitoring/prometheus.yml` (`scrape_interval: 15s`, `scrape_timeout: 12s`).

| Job                    | Target                        | Collects                                              |
| ---------------------- | ----------------------------- | ----------------------------------------------------- |
| `prometheus`           | `localhost:9090`              | Prometheus self-metrics                               |
| `node`                 | `node-exporter:9100`          | Host CPU, RAM, disk, network, hwmon and thermal zones |
| `amd-gpu`              | `amd-gpu-exporter:5000`       | GPU utilization, VRAM, temperature, power, clocks     |
| `llama-cpp`            | `llama-metrics-exporter:9090` | `llama-server` metrics per model plus exporter state  |
| `stable-diffusion-cpp` | `sd-metrics-exporter:9090`    | Image activity, upstream health, available models     |

## 📊 Dashboards

Provisioned from `monitoring/grafana/dashboards/` (reloaded every 30 s, UI edits disabled) against the default
`Prometheus` datasource.

| Dashboard              | File                    | Panels                                                                             |
| ---------------------- | ----------------------- | ---------------------------------------------------------------------------------- |
| AMD GPU                | `gpu.json`              | Shader clock, temperature, power draw, VRAM used/total/%, clocks, thermals, health |
| Host                   | `node.json`             | CPU, load, memory, uptime, CPU temperature, root disk, network throughput          |
| `llama.cpp`            | `llama-cpp.json`        | Average prefill and inference throughput by model, tokens/s over time              |
| `stable-diffusion.cpp` | `stable-diffusion.json` | Server state, requests in flight, upstream health, discovered models, activity     |

## 🔢 Exporter metrics

### `llama-metrics-exporter`

Passes through `llama-server`'s `llamacpp:*` metrics (e.g. `llamacpp:tokens_predicted_total`,
`llamacpp:prompt_tokens_total`) with a `model` label added, plus its own state:

| Metric                                       | Meaning                                                        |
| -------------------------------------------- | -------------------------------------------------------------- |
| `llama_metrics_exporter_up`                  | Exporter completed its scrape cycle                            |
| `llama_metrics_exporter_idle`                | `1` while `llama-manager` reports no recent inference activity |
| `llama_metrics_exporter_discovered_models`   | Models discovered via `/models`                                |
| `llama_metrics_exporter_loaded_models`       | Models with `status.value="loaded"`                            |
| `llama_metrics_exporter_metrics_scrape_up`   | `/metrics` scraped for at least one model                      |
| `llama_metrics_exporter_model_loaded{model}` | Model currently loaded                                         |
| `llama_metrics_exporter_model_up{model}`     | Model's `/metrics` scraped this cycle                          |

### `sd-metrics-exporter`

| Metric                                                | Meaning                              |
| ----------------------------------------------------- | ------------------------------------ |
| `sd_metrics_exporter_up`                              | Exporter completed its scrape cycle  |
| `sd_metrics_exporter_server_up`                       | `sd-server` answered `/v1/models`    |
| `sd_metrics_exporter_manager_up`                      | `sd-manager` answered `/status`      |
| `sd_metrics_exporter_idle`                            | `1` while no recent image activity   |
| `sd_metrics_exporter_active_requests`                 | Image requests currently in flight   |
| `sd_metrics_exporter_last_activity_timestamp_seconds` | Unix time of the last image activity |
| `sd_metrics_exporter_discovered_models`               | Models advertised by `sd-server`     |
| `sd_metrics_exporter_model_available{model}`          | Model advertised by `sd-server`      |

## 💤 Idle-aware scraping

Scraping `llama-server /metrics` directly in router mode causes model load/unload thrashing (`monitoring/prometheus.yml`).
`llama-metrics-exporter` asks `llama-manager /status` first:

- **Active** — scrape `/metrics` for each loaded model; the payload is refreshed in the background and cached for
  `CACHE_TTL_SECONDS` (5 s).
- **Idle** — serve the last active counter values plus a fresh `/models` snapshot; perform one catch-up scrape after
  unseen activity so short requests between scrapes are not lost.

See [Idle VRAM unloading](gpu-management.md#-idle-vram-unloading) for the manager side.

---

## ❓ FAQ

### Why do the `llama.cpp` panels flatline when nothing is running?

Idle mode serves the last counter values on purpose, so rates drop to zero rather than the scrape waking a model.

### How do I add or change a dashboard?

Edit or add a JSON file in `monitoring/grafana/dashboards/`. UI edits are disabled for provisioned dashboards, so
export from the UI and commit the JSON; Grafana picks changes up within 30 seconds.

### Is Grafana safe with anonymous admin?

Only within the single-tenant design: Grafana is reachable solely over Tailscale or loopback. See
[Architecture](architecture.md).

### How long is history kept?

30 days (`--storage.tsdb.retention.time=30d`) in the `prometheus-data` volume, which `cluster stop --volumes` and
`cluster cleanup` delete.
