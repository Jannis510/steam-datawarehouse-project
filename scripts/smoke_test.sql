-- Minimal smoke tests to confirm the DWH is populated and keys link up.

SELECT current_database() AS db_name, NOW() AS checked_at;

SELECT 'dim_timestamp' AS table_name, COUNT(*) AS row_count FROM dwh.dim_timestamp;
SELECT 'dim_app' AS table_name, COUNT(*) AS row_count FROM dwh.dim_app;
SELECT 'dim_update_typ' AS table_name, COUNT(*) AS row_count FROM dwh.dim_update_typ;
SELECT 'dim_update_content' AS table_name, COUNT(*) AS row_count FROM dwh.dim_update_content;
SELECT 'fact_news' AS table_name, COUNT(*) AS row_count FROM dwh.fact_news;
SELECT 'fact_steamspy_stats' AS table_name, COUNT(*) AS row_count FROM dwh.fact_steamspy_stats;

-- Basic null key checks (should be zero)
SELECT COUNT(*) AS fact_news_null_keys
FROM dwh.fact_news
WHERE app_id IS NULL OR update_id IS NULL OR timestamp_id IS NULL OR etl_run_id IS NULL;

SELECT COUNT(*) AS fact_steamspy_null_keys
FROM dwh.fact_steamspy_stats
WHERE app_id IS NULL OR timestamp_id IS NULL OR etl_run_id IS NULL;

-- Orphan checks (should be zero or very small)
SELECT COUNT(*) AS fact_news_orphan_content
FROM dwh.fact_news n
LEFT JOIN dwh.dim_update_content c
  ON c.app_id = n.app_id AND c.update_id = n.update_id
WHERE c.update_id IS NULL;

SELECT COUNT(*) AS fact_news_orphan_timestamp
FROM dwh.fact_news n
LEFT JOIN dwh.dim_timestamp t
  ON t.timestamp_id = n.timestamp_id
WHERE t.timestamp_id IS NULL;

SELECT COUNT(*) AS fact_steamspy_orphan_timestamp
FROM dwh.fact_steamspy_stats s
LEFT JOIN dwh.dim_timestamp t
  ON t.timestamp_id = s.timestamp_id
WHERE t.timestamp_id IS NULL;
