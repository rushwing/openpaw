.PHONY: install dev dev-pi test test-contracts test-unit test-integration lint typecheck \
        validate-contracts setup-local setup-pi clean fmt

# ── Development setup ──────────────────────────────────────────────────────────

install:
	uv sync --all-extras

dev:
	uv run uvicorn apps.api_gateway.main:app --reload --port 8000

dev-pi:
	LOCAL_ONLY=true uv run uvicorn apps.api_gateway.main:app --reload --port 8000

dev-worker:
	uv run python -m apps.worker_orchestrator.main

dev-bot:
	uv run python -m apps.telegram_bot.main

# ── Testing ────────────────────────────────────────────────────────────────────

test:
	uv run pytest tests/ -v --cov=. --cov-report=term-missing

test-unit:
	uv run pytest tests/unit/ -v

test-integration:
	uv run pytest tests/integration/ -v

test-contracts:
	uv run pytest tests/contracts/ -v

# ── Code quality ───────────────────────────────────────────────────────────────

lint:
	uv run ruff check . --fix

fmt:
	uv run ruff format .

typecheck:
	uv run mypy apps/ domains/ workflows/ adapters/ platform/

validate-contracts:
	uv run python -m platform.contracts.validate

# ── Local infrastructure (Docker Compose) ─────────────────────────────────────

setup-local:
	docker compose -f deploy/local-pi/docker-compose.yml up -d

setup-local-stop:
	docker compose -f deploy/local-pi/docker-compose.yml down

setup-pi: setup-local
	@echo "Pi services started. API will run on port 8000."

# ── Housekeeping ───────────────────────────────────────────────────────────────

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	rm -rf .coverage htmlcov/ .mypy_cache/ .ruff_cache/ dist/

# ── DB migrations (placeholder — add Alembic later) ───────────────────────────

db-migrate:
	uv run alembic upgrade head

db-rollback:
	uv run alembic downgrade -1
