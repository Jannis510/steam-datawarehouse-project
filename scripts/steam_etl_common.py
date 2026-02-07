#!/usr/bin/env python3
from __future__ import annotations

import logging
import os
import time
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Dict, Iterable, Optional, Tuple

import psycopg2
import psycopg2.extras
import requests
from dotenv import load_dotenv

STEAM_NEWS_URL = "https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/"
STEAMSPY_ALL_URL = "https://steamspy.com/api.php?request=all"

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")


def load_env_if_present() -> None:
    # optional: falls du lokal .env nutzt
    load_dotenv(override=False)


def get_db_connection():
    host = os.getenv("POSTGRES_HOST") or os.getenv("DB_HOST") or "postgres"
    port = int(os.getenv("POSTGRES_PORT") or os.getenv("DB_PORT") or 5432)
    db = os.getenv("POSTGRES_DB") or os.getenv("DB_NAME") or "dwh"
    user = os.getenv("POSTGRES_USER") or os.getenv("DB_USER") or "dwh"
    pw = os.getenv("POSTGRES_PASSWORD") or os.getenv("DB_PASSWORD") or ""

    logging.info(
        "DB env POSTGRES_HOST=%r POSTGRES_PORT=%r POSTGRES_DB=%r POSTGRES_USER=%r",
        os.getenv("POSTGRES_HOST"),
        os.getenv("POSTGRES_PORT"),
        os.getenv("POSTGRES_DB"),
        os.getenv("POSTGRES_USER"),
    )

    return psycopg2.connect(host=host, port=port, dbname=db, user=user, password=pw)


# ----------------------------
# HTTP helpers (minimal robust)
# ----------------------------
def http_get_json(
    session: requests.Session,
    url: str,
    *,
    params: Optional[dict] = None,
    timeout: int = 30,
    retries: int = 3,
):
    last_exc: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            r = session.get(url, params=params, timeout=timeout)
            r.raise_for_status()
            return r.json()
        except Exception as exc:  # noqa: BLE001
            last_exc = exc
            sleep_s = min(2**attempt, 8)
            logging.warning(
                "HTTP failed (%s/%s) url=%s err=%s; retrying in %ss",
                attempt,
                retries,
                url,
                exc,
                sleep_s,
            )
            time.sleep(sleep_s)
    raise last_exc  # type: ignore[misc]


def fetch_steamspy_data(session: requests.Session) -> Dict[str, dict]:
    logging.info("Fetching SteamSpy dataset ...")
    payload = http_get_json(session, STEAMSPY_ALL_URL, timeout=60, retries=3)
    logging.info("Fetched %s app entries from SteamSpy", len(payload))
    return payload


def fetch_news_for_app(
    session: requests.Session,
    app_id: int,
    *,
    page_size: int = 100,
    max_pages: Optional[int] = None,
    cutoff_ts: Optional[datetime] = None,
) -> tuple[list[dict], dict]:
    """
    Fetch Steam news for one app via 'enddate' pagination (robust).
    - Uses enddate = oldest_item_date - 1 to go backwards in time.
    - Deduplicates by gid within this app.
    - If cutoff_ts is set, stop paging once items are older than cutoff,
      and return only items newer than cutoff.
    """
    all_items: list[dict] = []
    seen_gids: set[str] = set()

    page = 0
    enddate: Optional[int] = None
    total_expected: Optional[int] = None

    forbidden = False
    rate_limited_hits = 0
    dup = 0

    cutoff_epoch = int(cutoff_ts.timestamp()) if cutoff_ts else None

    while True:
        params = {"appid": app_id, "count": page_size}
        if enddate is not None:
            params["enddate"] = enddate

        r = session.get(STEAM_NEWS_URL, params=params, timeout=30)

        if r.status_code == 403:
            forbidden = True
            logging.info("Steam News forbidden for app %s. Skipping.", app_id)
            break

        if r.status_code == 429:
            rate_limited_hits += 1
            retry_after = int(r.headers.get("Retry-After", "5"))
            retry_after = max(1, min(retry_after, 60))
            logging.warning("Rate limited for app %s. Sleeping %ss", app_id, retry_after)
            time.sleep(retry_after)
            continue

        r.raise_for_status()
        data = r.json()
        appnews = data.get("appnews", {}) or {}
        items = appnews.get("newsitems", []) or []

        if total_expected is None:
            total_expected = appnews.get("count")

        if not items:
            break

        new = 0
        oldest = None
        reached_cutoff = False

        for it in items:
            gid = str(it.get("gid"))
            if not gid:
                continue
            if gid in seen_gids:
                dup += 1
                continue
            seen_gids.add(gid)

            d = it.get("date")
            if isinstance(d, int):
                oldest = d if oldest is None else min(oldest, d)
                if cutoff_epoch is not None and d <= cutoff_epoch:
                    reached_cutoff = True
                    continue

            all_items.append(it)
            new += 1

        page += 1

        logging.info(
            "News page app=%s page=%s enddate=%s got=%s new=%s dup=%s unique_total=%s total=%s oldest=%s cutoff=%s",
            app_id,
            page,
            enddate,
            len(items),
            new,
            dup,
            len(all_items),
            total_expected,
            oldest,
            cutoff_ts,
        )

        if max_pages is not None and page >= max_pages:
            break
        if total_expected is not None and len(all_items) >= int(total_expected):
            break
        if len(items) < page_size:
            break
        if reached_cutoff:
            break
        if oldest is None:
            break

        enddate = oldest - 1

    meta = {
        "pages": page,
        "fetched": len(all_items),
        "unique_total": len(all_items),
        "duplicates": dup,
        "total_expected": total_expected,
        "forbidden": forbidden,
        "rate_limited_hits": rate_limited_hits,
        "last_enddate": enddate,
    }
    return all_items, meta


# ----------------------------
# DB upserts
# ----------------------------
def upsert_timestamp(cur, ts: datetime) -> int:
    cur.execute(
        """
        INSERT INTO dim_timestamp (ts)
        VALUES (%s)
        ON CONFLICT (ts) DO NOTHING
        RETURNING timestamp_id;
        """,
        (ts,),
    )
    row = cur.fetchone()
    if row:
        return row[0]

    cur.execute("SELECT timestamp_id FROM dim_timestamp WHERE ts = %s;", (ts,))
    return cur.fetchone()[0]


def create_etl_run(cur, run_type: str, status: str = "running") -> int:
    started_at = datetime.now(timezone.utc)
    cur.execute(
        """
        INSERT INTO dim_etl_run (run_type, status, started_at, updated_at)
        VALUES (%s, %s, %s, NOW())
        RETURNING etl_run_id;
        """,
        (run_type, status, started_at),
    )
    return cur.fetchone()[0]


def finalize_etl_run(cur, etl_run_id: Optional[int], status: str) -> None:
    if etl_run_id is None:
        return
    ended_at = datetime.now(timezone.utc)
    cur.execute(
        """
        UPDATE dim_etl_run
        SET status = %s,
            ended_at = %s,
            updated_at = NOW()
        WHERE etl_run_id = %s;
        """,
        (status, ended_at, etl_run_id),
    )


def upsert_app(cur, app: dict) -> int:
    app_id = int(app.get("appid"))
    name = app.get("name")
    dev = app.get("developer")
    pub = app.get("publisher")

    cur.execute(
        """
        INSERT INTO dim_app (app_id, app_name, developer, publisher, updated_at)
        VALUES (%s, %s, %s, %s, NOW())
        ON CONFLICT (app_id) DO UPDATE
        SET app_name   = COALESCE(EXCLUDED.app_name,  dim_app.app_name),
            developer  = COALESCE(EXCLUDED.developer, dim_app.developer),
            publisher  = COALESCE(EXCLUDED.publisher, dim_app.publisher),
            updated_at = NOW()
        RETURNING app_id;
        """,
        (app_id, name, dev, pub),
    )
    return cur.fetchone()[0]


def parse_owners_range(owners: Optional[str]) -> Tuple[Optional[int], Optional[int]]:
    if not owners or ".." not in owners:
        return None, None
    try:
        start, end = owners.split("..")
        start_clean = start.replace(",", "").strip()
        end_clean = end.replace(",", "").strip()
        return int(start_clean), int(end_clean)
    except ValueError:
        logging.warning("Could not parse owners range: %s", owners)
        return None, None


def parse_decimal(value: Optional[str], scale: int = 100) -> Optional[Decimal]:
    if value in (None, "", "0"):
        return Decimal("0")
    try:
        return (Decimal(value) / scale).quantize(Decimal("0.01"))
    except (InvalidOperation, ZeroDivisionError):
        logging.warning("Could not parse decimal value: %s", value)
        return None


def insert_steamspy_snapshot(cur, timestamp_id: int, etl_run_id: int, app: dict) -> None:
    owners_min, owners_max = parse_owners_range(app.get("owners"))
    cur.execute(
        """
        INSERT INTO fact_steamspy_stats (
            timestamp_id, etl_run_id, app_id, owners_min, owners_max, ccu, positive, negative,
            userscore, average_forever, median_forever, average_2weeks, median_2weeks,
            price, initialprice, discount
        ) VALUES (
            %s, %s, %s, %s, %s, %s, %s, %s,
            %s, %s, %s, %s, %s,
            %s, %s, %s
        );
        """,
        (
            timestamp_id,
            etl_run_id,
            int(app.get("appid")),
            owners_min,
            owners_max,
            app.get("ccu"),
            app.get("positive"),
            app.get("negative"),
            app.get("userscore"),
            app.get("average_forever"),
            app.get("median_forever"),
            app.get("average_2weeks"),
            app.get("median_2weeks"),
            parse_decimal(app.get("price")),
            parse_decimal(app.get("initialprice")),
            parse_decimal(app.get("discount"), scale=1),
        ),
    )


def get_update_type_id(cur, type_name: str) -> int:
    cur.execute(
        """
        INSERT INTO dim_update_typ (type_name, updated_at)
        VALUES (%s, NOW())
        ON CONFLICT (type_name) DO UPDATE
        SET updated_at = NOW()
        RETURNING update_type_id;
        """,
        (type_name,),
    )
    return cur.fetchone()[0]


def insert_news_items(
    cur,
    parent_app_id: int,
    news_items: Iterable[dict],
    timestamp_cache: Dict[datetime, int],
    update_type_cache: Dict[str, int],
    etl_run_id: int,
) -> dict:
    attempted = 0
    inserted_fact = 0
    inserted_content = 0

    skipped_missing = 0
    failed = 0

    conflict_content = 0
    conflict_fact = 0

    log_conflicts_limit = int(os.getenv("LOG_CONFLICTS_LIMIT", "20"))
    logged_conflicts = 0

    for item in news_items:
        attempted += 1
        try:
            cur.execute("SAVEPOINT news_item;")

            gid = str(item.get("gid") or "")
            if not gid:
                skipped_missing += 1
                cur.execute("RELEASE SAVEPOINT news_item;")
                continue

            title = item.get("title")
            url = item.get("url")
            if not title or not url:
                skipped_missing += 1
                logging.warning(
                    "Skip missing title/url app=%s gid=%s title=%s url=%s",
                    parent_app_id,
                    gid,
                    bool(title),
                    bool(url),
                )
                cur.execute("RELEASE SAVEPOINT news_item;")
                continue

            tags = item.get("tags") or []
            event_ts = datetime.fromtimestamp(item.get("date", 0), tz=timezone.utc).replace(tzinfo=None)

            timestamp_id = timestamp_cache.get(event_ts)
            if timestamp_id is None:
                timestamp_id = upsert_timestamp(cur, event_ts)
                timestamp_cache[event_ts] = timestamp_id

            update_type_id = None
            if tags:
                tag_key = str(tags[0])
                update_type_id = update_type_cache.get(tag_key)
                if update_type_id is None:
                    update_type_id = get_update_type_id(cur, tag_key)
                    update_type_cache[tag_key] = update_type_id

            # 1) dim_update_content (PK: app_id, update_id)
            cur.execute(
                """
                INSERT INTO dim_update_content (
                    app_id, update_id, content_raw, author, feedlabel, feedname, feedtype,
                    is_external_url, tags_raw
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (app_id, update_id) DO NOTHING;
                """,
                (
                    parent_app_id,
                    gid,
                    item.get("contents"),
                    item.get("author"),
                    item.get("feedlabel"),
                    item.get("feedname"),
                    item.get("feed_type"),
                    bool(item.get("is_external_url")),
                    psycopg2.extras.Json(tags),
                ),
            )
            if cur.rowcount == 1:
                inserted_content += 1
            else:
                conflict_content += 1

            # 2) fact_news (PK: app_id, update_id)
            cur.execute(
                """
                INSERT INTO fact_news (
                    app_id, update_id, timestamp_id, etl_run_id, update_type_id, title, url
                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (app_id, update_id) DO NOTHING;
                """,
                (parent_app_id, gid, timestamp_id, etl_run_id, update_type_id, title, url),
            )
            if cur.rowcount == 1:
                inserted_fact += 1
            else:
                conflict_fact += 1

            cur.execute("RELEASE SAVEPOINT news_item;")

        except Exception as exc:  # noqa: BLE001
            failed += 1
            cur.execute("ROLLBACK TO SAVEPOINT news_item;")
            cur.execute("RELEASE SAVEPOINT news_item;")
            logging.exception("ERROR news item app=%s gid=%s: %s", parent_app_id, item.get("gid"), exc)

    return {
        "attempted": attempted,
        "inserted_fact_news": inserted_fact,
        "inserted_dim_update_content": inserted_content,
        "conflict_fact_news": conflict_fact,
        "conflict_dim_update_content": conflict_content,
        "skipped_missing_fields": skipped_missing,
        "failed": failed,
    }


def fetch_latest_news_timestamps(cur) -> Dict[int, datetime]:
    cur.execute(
        """
        SELECT n.app_id, MAX(t.ts) AS latest_ts
        FROM dwh.fact_news n
        JOIN dwh.dim_timestamp t ON t.timestamp_id = n.timestamp_id
        GROUP BY n.app_id;
        """
    )
    return {row[0]: row[1] for row in cur.fetchall()}


def get_tuning():
    log_every = int(os.getenv("LOG_EVERY", "50"))
    sleep_between_apps = float(os.getenv("NEWS_SLEEP_S", "0"))
    page_size = int(os.getenv("NEWS_PAGE_SIZE", "100"))
    max_pages_env = int(os.getenv("NEWS_MAX_PAGES", "0"))
    max_pages = None if max_pages_env <= 0 else max_pages_env
    commit_every_apps = int(os.getenv("COMMIT_EVERY_APPS", "25"))

    return log_every, sleep_between_apps, page_size, max_pages, commit_every_apps
