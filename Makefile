# Load runtime settings from .env (or fallback to .env.example)
ifneq (,$(wildcard .env))
include .env
else
include .env.example
endif
export

OLLAMA_SERVICE ?= ollama

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

ollama-model-run:
	@test -n "$(MODEL)" || (echo "MODEL is not set in .env" && exit 1)
	@docker compose ps -q $(OLLAMA_SERVICE) | grep -q . || (echo "Service '$(OLLAMA_SERVICE)' is not running" && exit 1)
	docker compose exec $(OLLAMA_SERVICE) ollama run "$(MODEL)"

ollama-model-stop:
	@test -n "$(MODEL)" || (echo "MODEL is not set in .env" && exit 1)
	@docker compose ps -q $(OLLAMA_SERVICE) | grep -q . || (echo "Service '$(OLLAMA_SERVICE)' is not running" && exit 1)
	docker compose exec $(OLLAMA_SERVICE) ollama stop "$(MODEL)"
