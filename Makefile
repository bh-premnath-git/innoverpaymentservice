SHELL := /bin/bash

.PHONY: up down rebuild logs ps proto urls smoke-test nuke restart health workers publish-apis

# Start all services (WSO2 setup runs automatically)
up:
	docker compose up -d --build
	@echo ""
	@echo "✅ All services started!"
	@echo ""
	@echo "📊 WSO2 setup will run automatically via wso2-setup container"
	@echo "   Monitor with: docker logs -f wso2-setup"
	@echo ""
	@echo "⏳ Estimated setup time: 2-3 minutes"

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
	@echo "=== Service URLs (Financial Platform) ==="
	@echo "WSO2 IS Admin:   https://localhost:9444/carbon (admin/admin)"
	@echo "WSO2 IS OAuth2:  https://auth.127.0.0.1.sslip.io"
	@echo "WSO2 APIM Admin: https://localhost:9443/carbon (admin/admin)"
	@echo "WSO2 Dev Portal: https://localhost:9443/devportal"
	@echo "API Gateway:     http://localhost:8280 (HTTP)"
	@echo "API Gateway:     https://localhost:8243 (HTTPS)"
	@echo "Jaeger UI:       http://localhost:16686"
	@echo "CockroachDB UI:  http://localhost:8082"
	@echo "Redis:           localhost:6379"
	@echo "Redpanda:        localhost:9092"

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

# Database shell (uses DB_NAME from .env if available)
db-shell:
	docker compose exec cockroach1 /cockroach/cockroach sql --insecure --host=cockroach1:26257 --database=$${DB_NAME:-innover}

	docker compose exec redis sh -c 'redis-cli -a "$$REDIS_PASSWORD"'

# Kafka topic list
	docker compose exec redpanda rpk topic list --brokers redpanda:9092

# Manual setup (if wso2-setup container fails or for re-configuration)
setup:
	@echo "Running manual WSO2 APIM + IS setup..."
	@docker compose run --rm wso2-setup
	@echo ""
	@echo "✅ Setup complete! WSO2 IS and APIM configured."

# Check WSO2 setup status
setup-status:
	@echo "=== WSO2 Setup Status ==="
	@docker logs wso2-setup 2>&1 | tail -30 || echo "Setup container not found or not started yet"

# WSO2 troubleshooting targets
wso2-check:
	@echo "=== WSO2 Services Status ==="
	@docker ps -a --filter "name=wso2" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

wso2-logs:
	@echo "=== WSO2 AM Recent Logs ==="
	@docker logs innover-wso2am-1 --tail 50 2>&1 | grep -i "error\|exception\|failed" || echo "No errors found"
	@echo ""
	@echo "=== WSO2 Setup Logs ==="
	@docker logs wso2-setup 2>&1 | tail -30 || echo "Setup not run yet"

wso2-restart:
	@echo "Restarting WSO2 services..."
	@docker compose restart wso2am
	@echo "Waiting for WSO2 AM to be healthy..."
	@sleep 30
	@docker compose up -d wso2-setup

wso2-reset:
	@echo "⚠️  Resetting WSO2 data (removes volumes)..."
	@docker compose stop wso2am wso2is wso2-setup wso2is-init
	@docker volume rm innover_wso2am-data innover_wso2is-data 2>/dev/null || true
	@echo "Starting fresh WSO2 setup..."
	@docker compose up -d wso2is wso2am
	@echo "Wait for services to be healthy, then run: make setup"

# Enable WSO2 IS Key Manager (for production)
wso2-enable-km:
	@echo "Enabling WSO2 IS as Key Manager..."

# Publish APIs to WSO2
publish-apis:
	@docker compose run --rm wso2-setup

# Test complete end-to-end flow
test:
	@echo "=== Testing Complete System: OAuth2 → WSO2 AM → All APIs ==="
	python3 test_auth_flow.py

# Help
help:
	@echo "=== Available Targets (Financial Platform) ==="
	@echo ""
	@echo "  make up              - Start all services (WSO2 IS + APIM)"
	@echo "  make down            - Stop and remove containers"
	@echo "  make nuke            - Remove everything (containers, volumes, images)"
	@echo "  make rebuild         - Rebuild all images without cache"
	@echo "  make restart-<svc>   - Restart specific service"
	@echo ""
	@echo "Monitoring:"
	@echo "  make ps              - Show container status"
	@echo "  make health          - Show health status of all containers"
	@echo "  make logs            - Tail logs from all services"
	@echo "  make logs-<svc>      - Tail logs from specific service"
	@echo "  make urls            - Show all service URLs (WSO2 IS, APIM, etc.)"
	@echo ""
	@echo "Testing:"
	@echo "  make test            - Test WSO2 auth + API access (comprehensive)"
	@echo "  make smoke-test      - Run comprehensive smoke tests"
	@echo "  make workers         - Show Celery worker status"
	@echo "  make test-worker-<svc> - Send test task to worker"
	@echo ""
	@echo "Setup & Configuration:"
	@echo "  make setup           - Run manual WSO2 setup"
	@echo "  make setup-status    - Check WSO2 setup status"
	@echo "  make publish-apis    - Publish all APIs to WSO2 API Manager"
	@echo ""
	@echo "WSO2 Troubleshooting:"
	@echo "  make wso2-check      - Check WSO2 services status"
	@echo "  make wso2-logs       - View WSO2 error logs"
	@echo "  make wso2-restart    - Restart WSO2 services and re-run setup"
	@echo "  make wso2-reset      - Reset WSO2 data (fresh start)"
	@echo "  make wso2-enable-km  - Enable WSO2 IS as Key Manager (production)"
	@echo ""
	@echo "Development:"
	@echo "  make proto           - Generate protobuf files"
	@echo "  make db-shell        - Open CockroachDB SQL shell"
	@echo "  make redis-cli       - Open Redis CLI"
	@echo "  make kafka-topics    - List Kafka topics"

