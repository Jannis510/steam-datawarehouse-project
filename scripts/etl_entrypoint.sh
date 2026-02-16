#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"; }

INITIAL_SCRIPT="/app/scripts/steam_etl_initial.py"
INCR_SCRIPT="/app/scripts/steam_etl_incremental.py"

log "Starting INITIAL ETL run..."
python "${INITIAL_SCRIPT}"
log "INITIAL ETL finished."

cron_schedule="${ETL_CRON_SCHEDULE:-}"
if [[ -z "${cron_schedule}" ]]; then
  log "ETL_CRON_SCHEDULE not set. Exiting after initial run."
  exit 0
fi

log "Configuring cron with schedule: ${cron_schedule}"

# Persist selected environment variables for cron jobs.
env_file="/app/.cron_env"
( env | grep -E '^(POSTGRES_|LOG_|NEWS_|COMMIT_|ETL_|TZ)=' || true ) > "${env_file}"
chmod 0600 "${env_file}"

cron_file="/etc/cron.d/etl"
{
  echo "SHELL=/bin/sh"
  echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  # Run via /bin/sh -lc and stream output to container stdout/stderr.
  echo "${cron_schedule} root /bin/sh -lc 'python /app/scripts/run_incremental_cron.py >> /proc/1/fd/1 2>&1'"
} > "${cron_file}"

chmod 0644 "${cron_file}"

log "Cron env written to ${env_file} (without password):"
( grep -E '^(POSTGRES_HOST|POSTGRES_PORT|POSTGRES_DB|POSTGRES_USER)=' "${env_file}" || true ) | sed 's/^/  /'

log "Starting cron in foreground..."
exec cron -f
