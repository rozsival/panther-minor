# Start Ollama cluster
start:
	docker compose up -d

# Stop Ollama cluster
stop:
	docker compose down

# Create/update the model from its local Modelfile inside the running Ollama service
model-create:
	@test -n "$(MODEL)" || (echo "MODEL is not set in .env" && exit 1)
	@docker compose ps -q ollama | grep -q . || (echo "Service 'ollama' is not running" && exit 1)
	docker compose exec ollama ollama create "$(MODEL)" -f "/models/$(MODEL)/Modelfile"

# Unload the model from memory
model-stop:
	@test -n "$(MODEL)" || (echo "MODEL is not set in .env" && exit 1)
	@docker compose ps -q ollama | grep -q . || (echo "Service 'ollama' is not running" && exit 1)
	docker compose exec ollama ollama stop "$(MODEL)"

# Remove the model from Ollama
model-remove:
	@test -n "$(MODEL)" || (echo "MODEL is not set in .env" && exit 1)
	@docker compose ps -q ollama | grep -q . || (echo "Service 'ollama' is not running" && exit 1)
	docker compose exec ollama ollama rm "$(MODEL)"

# Remove all Docker resources associated with the Ollama cluster
cleanup: stop
	docker network prune
	docker volume prune
	docker container prune
	docker image prune

# View logs for Ollama service
ollama-logs:
	docker compose logs -f ollama

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
