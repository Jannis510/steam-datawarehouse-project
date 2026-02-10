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
        f.average_forever,
        f.median_forever,
        f.average_2weeks,
        f.median_2weeks,
        f.price,
        f.initialprice,
        f.discount,
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
    average_forever,
    median_forever,
    average_2weeks,
    median_2weeks,
    price,
    initialprice,
    discount,
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
    er.started_at AS etl_started_at,
    m.snapshot_date,
    m.ccu,
    m.owners_min,
    m.owners_max,
    m.userscore,
    m.positive,
    m.negative,
    m.average_forever,
    m.median_forever,
    m.average_2weeks,
    m.median_2weeks,
    m.price,
    m.initialprice,
    m.discount,
    COALESCE(n.news_count_7d, 0)  AS news_count_7d,
    COALESCE(n.news_count_30d, 0) AS news_count_30d,
    (m.ccu::numeric / NULLIF(COALESCE(n.news_count_30d, 0), 0)) AS ccu_per_news_30d
FROM dwh.vw_app_metrics_by_etl_run m
JOIN dwh.dim_app a ON a.app_id = m.app_id
JOIN dwh.dim_etl_run er ON er.etl_run_id = m.etl_run_id
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


-- ------------------------------------------------------------
-- View: vw_app_news_latest
-- Grain: 1 row per (app_id, update_id); includes row_number for latest-N per app.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.vw_app_news_latest AS
SELECT
    n.app_id,
    a.app_name,
    n.update_id,
    n.title,
    n.url,
    t.ts AS news_ts,
    t.ts::date AS news_date,
    c.author,
    c.feedlabel,
    c.feedname,
    c.feedtype,
    c.is_external_url,
    c.content_raw,
    ROW_NUMBER() OVER (
        PARTITION BY n.app_id
        ORDER BY t.ts DESC, n.update_id DESC
    ) AS rn
FROM dwh.fact_news n
JOIN dwh.dim_timestamp t ON t.timestamp_id = n.timestamp_id
JOIN dwh.dim_app a ON a.app_id = n.app_id
LEFT JOIN dwh.dim_update_content c
  ON c.app_id = n.app_id AND c.update_id = n.update_id;


-- ------------------------------------------------------------
-- View: vw_app_news_daily
-- Grain: 1 row per (app_id, news_date); daily news counts.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.vw_app_news_daily AS
SELECT
    n.app_id,
    a.app_name,
    t.date AS news_date,
    COUNT(*) AS news_count
FROM dwh.fact_news n
JOIN dwh.dim_timestamp t ON t.timestamp_id = n.timestamp_id
JOIN dwh.dim_app a ON a.app_id = n.app_id
GROUP BY n.app_id, a.app_name, t.date;


-- ------------------------------------------------------------
-- View: vw_app_timeseries_by_etl_run
-- Grain: 1 row per (etl_run_id, app_id); includes daily news count for CCU relation.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.vw_app_timeseries_by_etl_run AS
SELECT
    o.app_id,
    o.app_name,
    o.etl_run_id,
    o.etl_started_at,
    o.snapshot_date,
    o.ccu,
    o.owners_min,
    o.owners_max,
    o.userscore,
    o.positive,
    o.negative,
    o.average_forever,
    o.median_forever,
    o.average_2weeks,
    o.median_2weeks,
    o.price,
    o.initialprice,
    o.discount,
    o.news_count_7d,
    o.news_count_30d,
    COALESCE(d.news_count, 0) AS news_count_daily
FROM dwh.vw_app_overview_by_etl_run o
LEFT JOIN dwh.vw_app_news_daily d
  ON d.app_id = o.app_id AND d.news_date = o.snapshot_date;


-- ------------------------------------------------------------
-- View: vw_app_changes_by_etl_run
-- Grain: 1 row per (etl_run_id, app_id); deltas vs previous run for same app.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.vw_app_changes_by_etl_run AS
WITH ordered AS (
    SELECT
        o.*,
        LAG(o.ccu) OVER (PARTITION BY o.app_id ORDER BY o.etl_started_at, o.etl_run_id) AS prev_ccu,
        LAG(o.owners_min) OVER (PARTITION BY o.app_id ORDER BY o.etl_started_at, o.etl_run_id) AS prev_owners_min,
        LAG(o.owners_max) OVER (PARTITION BY o.app_id ORDER BY o.etl_started_at, o.etl_run_id) AS prev_owners_max,
        LAG(o.positive) OVER (PARTITION BY o.app_id ORDER BY o.etl_started_at, o.etl_run_id) AS prev_positive,
        LAG(o.negative) OVER (PARTITION BY o.app_id ORDER BY o.etl_started_at, o.etl_run_id) AS prev_negative,
        LAG(o.userscore) OVER (PARTITION BY o.app_id ORDER BY o.etl_started_at, o.etl_run_id) AS prev_userscore,
        LAG(o.price) OVER (PARTITION BY o.app_id ORDER BY o.etl_started_at, o.etl_run_id) AS prev_price,
        LAG(o.initialprice) OVER (PARTITION BY o.app_id ORDER BY o.etl_started_at, o.etl_run_id) AS prev_initialprice,
        LAG(o.discount) OVER (PARTITION BY o.app_id ORDER BY o.etl_started_at, o.etl_run_id) AS prev_discount,
        LAG(o.news_count_7d) OVER (PARTITION BY o.app_id ORDER BY o.etl_started_at, o.etl_run_id) AS prev_news_count_7d,
        LAG(o.news_count_30d) OVER (PARTITION BY o.app_id ORDER BY o.etl_started_at, o.etl_run_id) AS prev_news_count_30d
    FROM dwh.vw_app_overview_by_etl_run o
)
SELECT
    app_id,
    app_name,
    etl_run_id,
    etl_started_at,
    snapshot_date,
    ccu,
    owners_min,
    owners_max,
    userscore,
    positive,
    negative,
    average_forever,
    median_forever,
    average_2weeks,
    median_2weeks,
    price,
    initialprice,
    discount,
    news_count_7d,
    news_count_30d,
    (ccu - prev_ccu) AS delta_ccu,
    (owners_min - prev_owners_min) AS delta_owners_min,
    (owners_max - prev_owners_max) AS delta_owners_max,
    (positive - prev_positive) AS delta_positive,
    (negative - prev_negative) AS delta_negative,
    (userscore - prev_userscore) AS delta_userscore,
    (price - prev_price) AS delta_price,
    (initialprice - prev_initialprice) AS delta_initialprice,
    (discount - prev_discount) AS delta_discount,
    (news_count_7d - prev_news_count_7d) AS delta_news_count_7d,
    (news_count_30d - prev_news_count_30d) AS delta_news_count_30d
FROM ordered;


-- ------------------------------------------------------------
-- View: vw_app_overview_latest_by_app
-- Grain: 1 row per app_id; latest successful ETL run per app.
-- Use: KPI Cards in App-Detail-Drilldown (correct "current" values).
-- Depends on: vw_app_overview_by_etl_run (existing)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.vw_app_overview_latest_by_app AS
SELECT *
FROM (
    SELECT
        o.*,
        ROW_NUMBER() OVER (
            PARTITION BY o.app_id
            ORDER BY o.etl_started_at DESC, o.etl_run_id DESC
        ) AS rn
    FROM dwh.vw_app_overview_by_etl_run o
) x
WHERE x.rn = 1;
