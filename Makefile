# Start Ollama cluster
start:
	docker compose up -d

# Stop Ollama cluster
stop:
	docker compose down

# Remove all Docker resources associated with the Ollama cluster
cleanup: stop
	docker network prune
	docker volume prune
	docker container prune
	docker image prune

# View logs for Ollama service
ollama-logs:
	docker compose logs -f ollama

# View logs for Ollama model initialization
ollama-model-init-logs:
	docker compose logs -f ollama-model-init

# View logs for Open WebUI
webui-logs:
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

