# -- llama.cpp cluster --------------------------------------------------------

# Start cluster
start:
	docker compose up -d

# Stop cluster
stop:
	docker compose down

# Remove all Docker resources associated with the cluster
cleanup:
	docker compose down -v --rmi all --remove-orphans

# -- Logs ---------------------------------------------------------------------

# View logs for llama.cpp service
llama-cpp-logs:
	docker compose logs -f llama-cpp

# View logs for Open WebUI
open-webui-logs:
	docker compose logs -f open-webui

# View logs for Prometheus
prometheus-logs:
	docker compose logs -f prometheus

# View logs for Grafana
grafana-logs:
	docker compose logs -f grafana

# View logs for Node Exporter
node-exporter-logs:
	docker compose logs -f node-exporter

# View logs for AMD GPU Exporter
amd-gpu-exporter-logs:
	docker compose logs -f amd-gpu-exporter
