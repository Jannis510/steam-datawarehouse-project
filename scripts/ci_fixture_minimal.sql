-- scripts/ci_fixture_minimal.sql
-- Deterministic fixture data used by CI SQL assertions.

SET search_path TO dwh;

-- Reset DWH tables so assertions run against a known dataset.
TRUNCATE TABLE
  fact_news,
  dim_update_content,
  dim_update_typ,
  fact_steamspy_stats,
  dim_timestamp,
  dim_app,
  dim_etl_run
RESTART IDENTITY CASCADE;

INSERT INTO dim_etl_run (etl_run_id, run_type, status, started_at, ended_at)
VALUES
  (1, 'initial', 'success', '2026-01-01 00:00:00+00', '2026-01-01 00:10:00+00'),
  (2, 'incremental', 'success', '2026-01-02 00:00:00+00', '2026-01-02 00:08:00+00');

INSERT INTO dim_app (app_id, app_name, developer, publisher)
VALUES
  (100, 'Game A', 'Dev A', 'Pub A'),
  (200, 'Game B', 'Dev B', 'Pub B'),
  (300, 'Game C', 'Dev C', 'Pub C');

INSERT INTO dim_timestamp (timestamp_id, ts)
VALUES
  (1, '2026-01-01 00:00:00'),
  (2, '2026-01-02 00:00:00'),
  (3, '2025-12-31 12:00:00'),
  (4, '2026-01-01 12:00:00'),
  (5, '2026-01-01 18:00:00');

INSERT INTO dim_update_typ (update_type_id, type_name)
VALUES
  (1, 'patch');

INSERT INTO dim_update_content (app_id, update_id, content_raw, author, feedlabel, feedname, feedtype, is_external_url, tags_raw)
VALUES
  (100, 'u100-1', 'content 1', 'author a', 'label', 'feed', 0, false, '["patch"]'::jsonb),
  (100, 'u100-2', 'content 2', 'author a', 'label', 'feed', 0, false, '["patch"]'::jsonb),
  (200, 'u200-1', 'content 3', 'author b', 'label', 'feed', 0, false, '["patch"]'::jsonb);

INSERT INTO fact_news (app_id, update_id, timestamp_id, etl_run_id, update_type_id, title, url)
VALUES
  (100, 'u100-1', 3, 1, 1, 'title 1', 'https://example.com/1'),
  (100, 'u100-2', 4, 2, 1, 'title 2', 'https://example.com/2'),
  (200, 'u200-1', 5, 2, 1, 'title 3', 'https://example.com/3');

INSERT INTO fact_steamspy_stats (
  stats_id, timestamp_id, etl_run_id, app_id,
  owners_min, owners_max, ccu, positive, negative, userscore,
  average_forever, median_forever, average_2weeks, median_2weeks,
  price, initialprice, discount
)
VALUES
  (1, 1, 1, 100, 1000, 2000, 100, 90, 10, 80, 1000, 800, 100, 90, 29.99, 39.99, 25),
  (2, 2, 2, 100, 1100, 2100, 120, 95, 12, 81, 1010, 810, 105, 92, 27.99, 39.99, 30),
  (3, 1, 1, 200,  800, 1500,  40, 60, 15, 70,  900, 700,  80, 70, 19.99, 29.99, 20),
  (4, 2, 2, 200,  850, 1550,  50, 62, 16, 71,  910, 705,  85, 72, 18.99, 29.99, 25),
  (5, 2, 2, 300,  300,  900,  10, 20,  5, 55,  500, 400,  40, 35,  9.99, 14.99, 33);

SELECT setval(pg_get_serial_sequence('dwh.dim_etl_run', 'etl_run_id'),
              (SELECT COALESCE(MAX(etl_run_id), 1) FROM dwh.dim_etl_run),
              true);

SELECT setval(pg_get_serial_sequence('dwh.dim_timestamp', 'timestamp_id'),
              (SELECT COALESCE(MAX(timestamp_id), 1) FROM dwh.dim_timestamp),
              true);

SELECT setval(pg_get_serial_sequence('dwh.fact_steamspy_stats', 'stats_id'),
              (SELECT COALESCE(MAX(stats_id), 1) FROM dwh.fact_steamspy_stats),
              true);

SELECT setval(pg_get_serial_sequence('dwh.dim_update_typ', 'update_type_id'),
              (SELECT COALESCE(MAX(update_type_id), 1) FROM dwh.dim_update_typ),
              true);
