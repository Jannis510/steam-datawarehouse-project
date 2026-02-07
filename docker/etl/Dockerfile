FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN apt-get update \
    && apt-get install -y --no-install-recommends cron \
    && rm -rf /var/lib/apt/lists/*

COPY scripts ./scripts
COPY README.md ./

RUN chmod +x \
    /app/scripts/etl_entrypoint.sh \
    /app/scripts/steam_etl_initial.py \
    /app/scripts/steam_etl_incremental.py \
    /app/scripts/run_incremental_cron.py

CMD ["/app/scripts/etl_entrypoint.sh"]
