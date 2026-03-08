start:
	docker compose up -d

stop:
	docker compose down

cleanup: stop
	docker network prune
	docker volume prune
	docker container prune
	docker image prune

ollama-logs:
	docker compose logs -f ollama

ollama-puller-logs:
	docker compose logs -f ollama-puller

webui-logs:
	docker compose logs -f open-webui

prometheus-logs:
	docker compose logs -f prometheus

grafana-logs:
	docker compose logs -f grafana

node-exporter-logs:
	docker compose logs -f node-exporter

amd-gpu-exporter-logs:
	docker compose logs -f amd-gpu-exporter
