start:
	docker compose up -d

stop:
	docker compose down

vllm-logs:
	docker compose logs -f vllm