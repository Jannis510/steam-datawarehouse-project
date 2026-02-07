#!/usr/bin/env python3
import os
import subprocess
import sys

# Cron has almost no env. Copy env of PID 1 (entrypoint) into this process env.
with open("/proc/1/environ", "rb") as f:
    raw = f.read().split(b"\x00")

allow_prefixes = ("POSTGRES_", "LOG_", "NEWS_", "COMMIT_", "ETL_", "TZ")

for kv in raw:
    if not kv:
        continue
    k, _, v = kv.partition(b"=")
    k = k.decode("utf-8", "ignore")
    if k.startswith(allow_prefixes):
        os.environ[k] = v.decode("utf-8", "ignore")

rc = subprocess.call([sys.executable, "/app/scripts/steam_etl_incremental.py"])
raise SystemExit(rc)
