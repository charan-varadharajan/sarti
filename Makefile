.PHONY: backend-check backend-test docker-down docker-up mobile-check setup

setup:
	@test -f .env || cp .env.example .env
	python3 -m venv .venv
	.venv/bin/pip install -r backend/requirements-dev.txt
	cd mobile && flutter pub get

backend-test:
	cd backend && ../.venv/bin/pytest -m "not integration" --cov --cov-report=term-missing --cov-fail-under=0

backend-check:
	cd backend && ../.venv/bin/ruff format --check src tests alembic scripts_generate_openapi.py
	cd backend && ../.venv/bin/ruff check src tests alembic scripts_generate_openapi.py
	cd backend && ../.venv/bin/mypy
	cd backend && ../.venv/bin/bandit -q -r src

mobile-check:
	cd mobile && dart format --output=none --set-exit-if-changed lib test
	cd mobile && flutter analyze
	cd mobile && flutter test --coverage

docker-up:
	docker compose up --build --wait

docker-down:
	docker compose down
