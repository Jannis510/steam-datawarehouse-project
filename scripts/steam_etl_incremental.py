#!/usr/bin/env python3
from __future__ import annotations

import logging
import time
from datetime import datetime
from typing import Dict

import requests

from steam_etl_common import (
    create_etl_run,
    finalize_etl_run,
    fetch_latest_news_timestamps,
    fetch_news_for_app,
    fetch_steamspy_data,
    get_db_connection,
    get_tuning,
    insert_news_items,
    insert_steamspy_snapshot,
    load_env_if_present,
    upsert_app,
    upsert_timestamp,
)


def run_incremental() -> None:
    load_env_if_present()
    session = requests.Session()

    log_every, sleep_between_apps, page_size, max_pages, commit_every_apps = get_tuning()

    # Phase 0: SteamSpy (holt neue apps, updates metadata)
    steamspy_payload = fetch_steamspy_data(session)

    conn = get_db_connection()
    conn.autocommit = False

    timestamp_cache: Dict = {}
    update_type_cache: Dict = {}
    etl_run_id = None
    run_status = "failed"

    with conn:
        with conn.cursor() as cur:
            etl_run_id = create_etl_run(cur, "incremental")
        conn.commit()

        try:
            # ----------------------------
            # Phase 1: SteamSpy snapshot
            # ----------------------------
            t0 = time.time()
            with conn.cursor() as cur:
                run_ts = datetime.utcnow()
                run_timestamp_id = upsert_timestamp(cur, run_ts)
                logging.info("SteamSpy snapshot start: timestamp_id=%s", run_timestamp_id)

                total_apps = len(steamspy_payload)
                ok = 0
                failed = 0

                for i, (_key, app) in enumerate(steamspy_payload.items(), start=1):
                    app_id = app.get("appid")
                    name = app.get("name")
                    try:
                        cur.execute("SAVEPOINT app_ingest;")
                        upsert_app(cur, app)
                        insert_steamspy_snapshot(cur, run_timestamp_id, etl_run_id, app)
                        cur.execute("RELEASE SAVEPOINT app_ingest;")
                        ok += 1
                    except Exception as exc:  # noqa: BLE001
                        cur.execute("ROLLBACK TO SAVEPOINT app_ingest;")
                        cur.execute("RELEASE SAVEPOINT app_ingest;")
                        failed += 1
                        logging.exception("SteamSpy ingest failed app=%s (%s): %s", app_id, name, exc)

                    if i == 1 or i % log_every == 0 or i == total_apps:
                        logging.info("SteamSpy progress: %s/%s (ok=%s, failed=%s)", i, total_apps, ok, failed)

            conn.commit()
            logging.info("SteamSpy snapshot done in %.1fs", time.time() - t0)

            # ----------------------------
            # Phase 2: News incremental
            # ----------------------------
            with conn.cursor() as cur:
                cur.execute("SELECT app_id, app_name FROM dwh.dim_app ORDER BY app_id;")
                apps = cur.fetchall()

            with conn.cursor() as cur:
                latest_news_ts = fetch_latest_news_timestamps(cur)

            total_apps = len(apps)
            total_fetched = 0
            total_inserted_fact = 0
            total_inserted_content = 0
            total_failed_items = 0
            total_skipped_missing = 0
            total_forbidden_apps = 0
            total_rate_limited_hits = 0

            t1 = time.time()
            with conn.cursor() as cur:
                for idx, (app_id, app_name) in enumerate(apps, start=1):
                    per_app_t0 = time.time()
                    cutoff_ts = latest_news_ts.get(app_id)

                    logging.info(
                        "News incremental start %s/%s: app_id=%s name=%s cutoff=%s",
                        idx,
                        total_apps,
                        app_id,
                        app_name,
                        cutoff_ts,
                    )

                    try:
                        cur.execute("SAVEPOINT app_news;")

                        news_items, meta = fetch_news_for_app(
                            session,
                            app_id,
                            page_size=page_size,
                            max_pages=max_pages,
                            cutoff_ts=cutoff_ts,
                        )

                        fetched = int(meta.get("fetched", len(news_items)))
                        pages = int(meta.get("pages", 0))

                        total_fetched += fetched
                        total_rate_limited_hits += int(meta.get("rate_limited_hits", 0))
                        if bool(meta.get("forbidden", False)):
                            total_forbidden_apps += 1

                        stats = insert_news_items(
                            cur,
                            app_id,
                            news_items,
                            timestamp_cache,
                            update_type_cache,
                            etl_run_id,
                        )

                        total_inserted_fact += stats["inserted_fact_news"]
                        total_inserted_content += stats["inserted_dim_update_content"]
                        total_failed_items += stats["failed"]
                        total_skipped_missing += stats["skipped_missing_fields"]

                        cur.execute("RELEASE SAVEPOINT app_news;")

                        logging.info(
                            "News incremental done %s/%s: app_id=%s fetched=%s inserted_fact=%s inserted_content=%s "
                            "conflict_fact=%s conflict_content=%s skipped_missing=%s failed_items=%s pages=%s duration=%.2fs",
                            idx,
                            total_apps,
                            app_id,
                            fetched,
                            stats["inserted_fact_news"],
                            stats["inserted_dim_update_content"],
                            stats["conflict_fact_news"],
                            stats["conflict_dim_update_content"],
                            stats["skipped_missing_fields"],
                            stats["failed"],
                            pages,
                            time.time() - per_app_t0,
                        )

                    except Exception as exc:  # noqa: BLE001
                        cur.execute("ROLLBACK TO SAVEPOINT app_news;")
                        cur.execute("RELEASE SAVEPOINT app_news;")
                        logging.exception("News ingest failed app_id=%s (%s): %s", app_id, app_name, exc)

                    if sleep_between_apps > 0:
                        time.sleep(sleep_between_apps)

                    if commit_every_apps > 0 and idx % commit_every_apps == 0:
                        conn.commit()
                        logging.info("Committed after %s apps in news phase.", idx)

            conn.commit()
            logging.info(
                "News incremental phase done in %.1fs | apps=%s | fetched_total=%s | inserted_fact_total=%s | "
                "inserted_content_total=%s | forbidden_apps=%s | rate_limited_hits=%s | skipped_missing=%s | failed_items=%s",
                time.time() - t1,
                total_apps,
                total_fetched,
                total_inserted_fact,
                total_inserted_content,
                total_forbidden_apps,
                total_rate_limited_hits,
                total_skipped_missing,
                total_failed_items,
            )
            run_status = "success"
        except Exception:  # noqa: BLE001
            logging.exception("ETL incremental run failed.")
            raise
        finally:
            with conn.cursor() as cur:
                finalize_etl_run(cur, etl_run_id, run_status)
            conn.commit()

    logging.info("ETL incremental run finished successfully.")


if __name__ == "__main__":
    run_incremental()
