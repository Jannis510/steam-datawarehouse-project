CREATE OR REPLACE VIEW dwh.vw_app_metrics_by_etl_run AS
WITH ranked AS (
    SELECT
        f.etl_run_id,
        f.app_id,
        f.ccu,
        f.owners_min,
        f.owners_max,
        f.userscore,
        f.positive,
        f.negative,
        t.ts,
        ROW_NUMBER() OVER (
            PARTITION BY f.etl_run_id, f.app_id
            ORDER BY t.ts DESC
        ) AS rn
    FROM dwh.fact_steamspy_stats f
    JOIN dwh.dim_timestamp t ON t.timestamp_id = f.timestamp_id
)
SELECT
    etl_run_id,
    app_id,
    ccu,
    owners_min,
    owners_max,
    userscore,
    positive,
    negative,
    ts::date AS snapshot_date
FROM ranked
WHERE rn = 1;


-- ------------------------------------------------------------
-- View: vw_app_news_7d_30d_asof_etl_run
-- Grain: 1 row per (etl_run_id, app_id); rolling news counts anchored at etl_run.started_at (as-of, timestamp-precise).
-- Performance: consider only last 30 successful runs (change LIMIT as needed).
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.vw_app_news_7d_30d_asof_etl_run AS
WITH run_anchor AS (
    SELECT
        er.etl_run_id,
        er.started_at AS anchor_ts
    FROM dwh.dim_etl_run er
    WHERE er.status = 'success'
    ORDER BY er.started_at DESC, er.etl_run_id DESC
    LIMIT 30
),
news AS (
    SELECT
        n.app_id,
        t.ts AS news_ts
    FROM dwh.fact_news n
    JOIN dwh.dim_timestamp t ON t.timestamp_id = n.timestamp_id
)
SELECT
    ra.etl_run_id,
    n.app_id,
    COUNT(*) FILTER (
        WHERE n.news_ts <= ra.anchor_ts
          AND n.news_ts >= (ra.anchor_ts - INTERVAL '6 days')
    ) AS news_count_7d,
    COUNT(*) FILTER (
        WHERE n.news_ts <= ra.anchor_ts
          AND n.news_ts >= (ra.anchor_ts - INTERVAL '29 days')
    ) AS news_count_30d
FROM run_anchor ra
JOIN news n ON TRUE
GROUP BY ra.etl_run_id, n.app_id;


-- ------------------------------------------------------------
-- View: vw_app_overview_by_etl_run
-- Grain: 1 row per (etl_run_id, app_id); app name + metrics (from this run) + news counts (as-of this run).
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.vw_app_overview_by_etl_run AS
SELECT
    m.app_id,
    a.app_name,
    m.etl_run_id,
    m.snapshot_date,
    m.ccu,
    m.owners_min,
    m.owners_max,
    m.userscore,
    m.positive,
    m.negative,
    COALESCE(n.news_count_7d, 0)  AS news_count_7d,
    COALESCE(n.news_count_30d, 0) AS news_count_30d,
    (m.ccu::numeric / NULLIF(COALESCE(n.news_count_30d, 0), 0)) AS ccu_per_news_30d
FROM dwh.vw_app_metrics_by_etl_run m
JOIN dwh.dim_app a ON a.app_id = m.app_id
LEFT JOIN dwh.vw_app_news_7d_30d_asof_etl_run n
  ON n.app_id = m.app_id AND n.etl_run_id = m.etl_run_id;



-- ------------------------------------------------------------
-- View: vw_app_overview_latest_etl_run
-- Grain: 1 row per app_id; only rows from the latest successful ETL run (by started_at).
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.vw_app_overview_latest_etl_run AS
SELECT *
FROM dwh.vw_app_overview_by_etl_run
WHERE etl_run_id = (
    SELECT er.etl_run_id
    FROM dwh.dim_etl_run er
    WHERE er.status = 'success'
    ORDER BY er.started_at DESC, er.etl_run_id DESC
    LIMIT 1
);
