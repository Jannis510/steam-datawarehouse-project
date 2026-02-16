#!/usr/bin/env bash
set -euo pipefail

# Apply the DWH schema inside an already running Postgres container.
# Useful when the data volume predates the init scripts.

COMPOSE_CMD=${COMPOSE_CMD:-docker compose}
DB_NAME=${POSTGRES_DB:-dwh}
DB_USER=${POSTGRES_USER:-dwh}
SERVICE_NAME=${POSTGRES_SERVICE:-postgres}

# Execute schema SQL in the target service/container.
${COMPOSE_CMD} exec -T "${SERVICE_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" -f /docker-entrypoint-initdb.d/001_create_schema.sql
