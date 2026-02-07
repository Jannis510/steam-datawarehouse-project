#!/usr/bin/env bash
set -euo pipefail

# Apply the DWH schema inside the running Postgres container.
# Useful when the data volume already existed before the init script was added.

COMPOSE_CMD=${COMPOSE_CMD:-docker compose}
DB_NAME=${POSTGRES_DB:-dwh}
DB_USER=${POSTGRES_USER:-dwh}
SERVICE_NAME=${POSTGRES_SERVICE:-postgres}

# Ensure Postgres is up before executing the schema
${COMPOSE_CMD} exec -T "${SERVICE_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" -f /docker-entrypoint-initdb.d/001_create_schema.sql
