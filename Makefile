SHELL := /bin/bash

.PHONY: up down rebuild logs ps proto urls smoke-test nuke restart health workers

# Start all services
up:
	docker compose up -d --build

# Rebuild without cache
rebuild:
	docker compose build --no-cache

# View logs (all services)
logs:
	docker compose logs -f --tail=200

# View logs for specific service
logs-%:
	docker compose logs -f --tail=100 $*

# Stop and remove all containers, volumes, and networks
down:
	docker compose down -v

# Nuclear option: remove everything including images
nuke:
	docker compose down -v --rmi all
	docker system prune -af --volumes

# Restart specific service
restart-%:
	docker compose restart $*

# Show container status
ps:
	docker compose ps

# Check health of all services
health:
	@echo "=== Container Health Status ==="
	@docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.Health}}"

# Generate protobuf files
proto:
	bash ./generate_protos.sh

# Show all service URLs
urls:
	@echo "=== Service URLs ==="
	@echo "Keycloak Admin:  http://localhost:8081 (admin/admin)"
	@echo "Kong Proxy:      http://localhost:8000"
	@echo "Kong Admin:      http://localhost:8001"
	@echo "Jaeger UI:       http://localhost:16686"
	@echo "CockroachDB UI:  http://localhost:8082"
	@echo "Redis:           localhost:6379"
	@echo "Redpanda:        localhost:9092"
	@echo ""
	@echo "=== Kong API Routes ==="
	@echo "Profile:         http://localhost:8000/api/profile/health"
	@echo "Payment:         http://localhost:8000/api/payment/health"
	@echo "Forex:           http://localhost:8000/api/fx/health"
	@echo "Ledger:          http://localhost:8000/api/ledger/health"
	@echo "Wallet:          http://localhost:8000/api/wallet/health"
	@echo "Rule Engine:     http://localhost:8000/api/rules/health"

# Run comprehensive smoke tests
smoke-test:
	@chmod +x smoke-test.sh
	@./smoke-test.sh

# Monitor Celery workers
workers:
	@echo "=== Celery Worker Status ==="
	@for worker in profile-worker payment-worker forex-worker ledger-worker wallet-worker rule-engine-worker; do \
		echo ""; \
		echo "--- $$worker ---"; \
		docker compose exec -T $$worker celery -A celery_app.celery_app inspect active 2>/dev/null || echo "Worker not responding"; \
	done

# Quick test: send echo task to a worker
test-worker-%:
	@echo "Sending echo task to $* worker..."
	@docker compose exec -T $* python -c "from celery_app import celery_app; r = celery_app.send_task('tasks.echo', args=['Hello from make!'], queue='$*-tasks'); print(f'Task ID: {r.id}')"
	@echo "Check logs with: make logs-$*-worker"

# Database shell
db-shell:
	docker compose exec cockroach1 /cockroach/cockroach sql --insecure --host=cockroach1:26257 --database=innover

# Redis CLI
redis-cli:
	docker compose exec redis sh -c 'redis-cli -a "$$REDIS_PASSWORD"'

# Kafka topic list
kafka-topics:
	docker compose exec redpanda rpk topic list --brokers redpanda:9092

# Help
help:
	@echo "Available targets:"
	@echo "  make up              - Start all services"
	@echo "  make down            - Stop and remove containers"
	@echo "  make nuke            - Remove everything (containers, volumes, images)"
	@echo "  make rebuild         - Rebuild all images without cache"
	@echo "  make restart-<svc>   - Restart specific service"
	@echo "  make ps              - Show container status"
	@echo "  make health          - Show health status of all containers"
	@echo "  make logs            - Tail logs from all services"
	@echo "  make logs-<svc>      - Tail logs from specific service"
	@echo "  make urls            - Show all service URLs"
	@echo "  make smoke-test      - Run comprehensive smoke tests"
	@echo "  make workers         - Show Celery worker status"
	@echo "  make test-worker-<svc> - Send test task to worker"
	@echo "  make proto           - Generate protobuf files"
	@echo "  make db-shell        - Open CockroachDB SQL shell"
	@echo "  make redis-cli       - Open Redis CLI"
	@echo "  make kafka-topics    - List Kafka topics"

