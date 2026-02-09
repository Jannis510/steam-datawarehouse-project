#!/usr/bin/env sh
set -eu

DUMP_FILE="${POSTGRES_DUMP_FILE:-}"
SMOKE_TEST="${POSTGRES_SMOKE_TEST:-0}"
SMOKE_SQL="/opt/smoke_test.sql"

if [ -z "$DUMP_FILE" ]; then
  exit 0
fi

if [ ! -f "$DUMP_FILE" ]; then
  echo "POSTGRES_DUMP_FILE not found: $DUMP_FILE" >&2
  exit 1
fi

case "$DUMP_FILE" in
  *.sql)
    echo "Importing SQL dump: $DUMP_FILE"
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$DUMP_FILE"
    ;;
  *.dump|*.backup)
    echo "Importing custom dump: $DUMP_FILE"
    pg_restore --data-only --no-owner --no-privileges -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$DUMP_FILE"
    ;;
  *)
    echo "Unsupported dump format: $DUMP_FILE" >&2
    exit 1
    ;;
esac

if [ "$SMOKE_TEST" = "1" ] && [ -f "$SMOKE_SQL" ]; then
  echo "Running smoke test: $SMOKE_SQL"
  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SMOKE_SQL"
fi
