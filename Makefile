# -- llama.cpp cluster --------------------------------------------------------

# Start cluster
start: build
	docker compose up -d

# Stop cluster
stop:
	docker compose down

stop-volumes:
	docker compose down -v

# Remove all Docker resources associated with the cluster
cleanup:
	docker compose down -v --rmi all --remove-orphans

# Restart cluster
restart: stop start

# Build Docker images for the cluster
build:
	docker compose build

build-no-cache:
	docker compose build --no-cache

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

# View Nginx proxy logs
proxy-logs:
	docker compose logs -f proxy

# -- Utils --------------------------------------------------------------------

# Update repo from upstream
update:
	git fetch --prune
	git pull --rebase
