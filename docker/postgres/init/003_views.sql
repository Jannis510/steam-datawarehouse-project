-- Analysis views for Superset (Steam News + SteamSpy)

-- View: vw_app_latest_metrics
-- Grain: 1 row per app_id; latest SteamSpy snapshot.
CREATE OR REPLACE VIEW dwh.vw_app_latest_metrics AS
WITH ranked AS (
    SELECT
        f.app_id,
        f.ccu,
        f.owners_min,
        f.owners_max,
        f.userscore,
        f.positive,
        f.negative,
        t.ts,
        ROW_NUMBER() OVER (PARTITION BY f.app_id ORDER BY t.ts DESC) AS rn
    FROM dwh.fact_steamspy_stats f
    JOIN dwh.dim_timestamp t ON t.timestamp_id = f.timestamp_id
)
SELECT
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

-- View: vw_app_news_7d_30d
-- Grain: 1 row per app_id; rolling news counts using anchor_date from max dim_timestamp.
-- Assumption: anchor_date = max(dim_timestamp.ts::date) for reproducible windows.
CREATE OR REPLACE VIEW dwh.vw_app_news_7d_30d AS
WITH anchor AS (
    SELECT MAX(ts::date) AS anchor_date
    FROM dwh.dim_timestamp
),
news AS (
    SELECT
        n.app_id,
        t.ts::date AS news_date
    FROM dwh.fact_news n
    JOIN dwh.dim_timestamp t ON t.timestamp_id = n.timestamp_id
)
SELECT
    n.app_id,
    COUNT(*) FILTER (WHERE n.news_date >= a.anchor_date - INTERVAL '6 days') AS news_count_7d,
    COUNT(*) FILTER (WHERE n.news_date >= a.anchor_date - INTERVAL '29 days') AS news_count_30d
FROM news n
CROSS JOIN anchor a
GROUP BY n.app_id;

-- View: vw_app_overview
-- Grain: 1 row per app_id; app name + latest metrics + news counts.
CREATE OR REPLACE VIEW dwh.vw_app_overview AS
SELECT
    a.app_id,
    a.app_name,
    m.snapshot_date,
    m.ccu,
    m.owners_min,
    m.owners_max,
    m.userscore,
    m.positive,
    m.negative,
    n.news_count_7d,
    n.news_count_30d,
    (m.ccu::numeric / NULLIF(n.news_count_30d, 0)) AS ccu_per_news_30d
FROM dwh.dim_app a
LEFT JOIN dwh.vw_app_latest_metrics m ON m.app_id = a.app_id
LEFT JOIN dwh.vw_app_news_7d_30d n ON n.app_id = a.app_id;

-- View: vw_app_timeline_daily
-- Grain: 1 row per (app_id, date); combine daily SteamSpy snapshot with daily news count.
-- Assumption: daily SteamSpy value = latest snapshot within that day; news_count defaults to 0.
CREATE OR REPLACE VIEW dwh.vw_app_timeline_daily AS
WITH steamspy_daily AS (
    SELECT DISTINCT ON (f.app_id, t.ts::date)
        f.app_id,
        t.ts::date AS date,
        f.ccu,
        f.owners_min,
        f.owners_max
    FROM dwh.fact_steamspy_stats f
    JOIN dwh.dim_timestamp t ON t.timestamp_id = f.timestamp_id
    ORDER BY f.app_id, t.ts::date, t.ts DESC
),
news_daily AS (
    SELECT
        n.app_id,
        t.ts::date AS date,
        COUNT(*) AS news_count
    FROM dwh.fact_news n
    JOIN dwh.dim_timestamp t ON t.timestamp_id = n.timestamp_id
    GROUP BY n.app_id, t.ts::date
)
SELECT
    COALESCE(s.app_id, n.app_id) AS app_id,
    a.app_name,
    COALESCE(s.date, n.date) AS date,
    s.ccu,
    s.owners_min,
    s.owners_max,
    COALESCE(n.news_count, 0) AS news_count
FROM steamspy_daily s
FULL OUTER JOIN news_daily n
    ON n.app_id = s.app_id AND n.date = s.date
LEFT JOIN dwh.dim_app a
    ON a.app_id = COALESCE(s.app_id, n.app_id);

-- View: vw_update_type_daily
-- Grain: 1 row per (date, type_name); count news by update type.
CREATE OR REPLACE VIEW dwh.vw_update_type_daily AS
SELECT
    t.ts::date AS date,
    COALESCE(ut.type_name, 'unknown') AS type_name,
    COUNT(*) AS news_count
FROM dwh.fact_news n
JOIN dwh.dim_timestamp t ON t.timestamp_id = n.timestamp_id
LEFT JOIN dwh.dim_update_typ ut ON ut.update_type_id = n.update_type_id
GROUP BY t.ts::date, COALESCE(ut.type_name, 'unknown');
