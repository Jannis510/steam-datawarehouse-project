FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install cron for scheduled incremental ETL runs inside the container.
RUN apt-get update \
    && apt-get install -y --no-install-recommends cron \
    && rm -rf /var/lib/apt/lists/*

COPY scripts ./scripts
COPY README.md ./

# Ensure shell/python ETL scripts are executable for the runtime user.
RUN chmod +x \
    /app/scripts/etl_entrypoint.sh \
    /app/scripts/steam_etl_initial.py \
    /app/scripts/steam_etl_incremental.py \
    /app/scripts/run_incremental_cron.py

# Use a single entrypoint script to switch between initial and incremental modes.
CMD ["/app/scripts/etl_entrypoint.sh"]
