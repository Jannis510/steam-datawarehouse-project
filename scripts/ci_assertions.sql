-- scripts/ci_assertions.sql
-- Assertions for CI fixture-based SQL/view validation.
-- Fails with an exception if expected results are not met.

SET search_path TO dwh;

DO $$
DECLARE
  v_count BIGINT;
  v_metric NUMERIC;
BEGIN
  SELECT COUNT(*) INTO v_count FROM dwh.vw_app_overview_by_etl_run;
  IF v_count <> 5 THEN
    RAISE EXCEPTION 'Expected 5 rows in vw_app_overview_by_etl_run, got %', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count FROM dwh.vw_app_overview_latest_etl_run;
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'Expected 3 rows in vw_app_overview_latest_etl_run, got %', v_count;
  END IF;

  SELECT ccu_per_news_30d INTO v_metric
  FROM dwh.vw_app_overview_by_etl_run
  WHERE app_id = 100 AND etl_run_id = 2;

  IF v_metric IS NULL OR ABS(v_metric - 60) > 0.0001 THEN
    RAISE EXCEPTION 'Expected ccu_per_news_30d = 60 for app 100 run 2, got %', v_metric;
  END IF;

  SELECT delta_ccu INTO v_metric
  FROM dwh.vw_app_changes_by_etl_run
  WHERE app_id = 100 AND etl_run_id = 2;

  IF v_metric IS NULL OR v_metric <> 20 THEN
    RAISE EXCEPTION 'Expected delta_ccu = 20 for app 100 run 2, got %', v_metric;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM dwh.vw_app_news_latest
  WHERE app_id = 100 AND rn = 1;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Expected one latest news row for app 100, got %', v_count;
  END IF;
END $$;
