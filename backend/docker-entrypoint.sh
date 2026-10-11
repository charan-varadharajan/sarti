#!/bin/sh
set -eu

alembic upgrade head
exec uvicorn sarti_backend.main:app --host 0.0.0.0 --port 8000 --no-access-log
