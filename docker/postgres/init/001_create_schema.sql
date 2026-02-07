-- Schema definition for the Steam News & SteamSpy Data Warehouse
CREATE SCHEMA IF NOT EXISTS dwh;
SET search_path TO dwh;

-- Dimension: Timestamp
CREATE TABLE IF NOT EXISTS dim_timestamp (
    timestamp_id BIGSERIAL PRIMARY KEY,
    -- Store timestamps as UTC (without time zone) to keep generated columns immutable
    ts TIMESTAMP NOT NULL,
    date DATE GENERATED ALWAYS AS (ts::date) STORED,
    year INT GENERATED ALWAYS AS (EXTRACT(YEAR FROM ts)) STORED,
    month INT GENERATED ALWAYS AS (EXTRACT(MONTH FROM ts)) STORED,
    day INT GENERATED ALWAYS AS (EXTRACT(DAY FROM ts)) STORED,
    hour INT GENERATED ALWAYS AS (EXTRACT(HOUR FROM ts)) STORED,
    weekday INT GENERATED ALWAYS AS (EXTRACT(ISODOW FROM ts)) STORED,

    UNIQUE (ts)
);

-- Dimension: ETL run metadata
CREATE TABLE IF NOT EXISTS dim_etl_run (
    etl_run_id BIGSERIAL PRIMARY KEY,
    run_type TEXT NOT NULL,
    status TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Dimension: App metadata
CREATE TABLE IF NOT EXISTS dim_app (
    app_id INT PRIMARY KEY,
    app_name TEXT,
    developer TEXT,
    publisher TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Dimension: Update classification (tags)
CREATE TABLE IF NOT EXISTS dim_update_typ (
    update_type_id SERIAL PRIMARY KEY,
    type_name TEXT UNIQUE NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);


-- Dimension: Update content (Steam News)
CREATE TABLE IF NOT EXISTS dim_update_content (
    app_id INT NOT NULL REFERENCES dim_app(app_id),
    update_id TEXT NOT NULL,
    content_raw TEXT,
    author TEXT,
    feedlabel TEXT,
    feedname TEXT,
    feedtype INT,
    is_external_url BOOLEAN,
    tags_raw JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (app_id, update_id)
);

-- Fact: Steam News events
CREATE TABLE IF NOT EXISTS fact_news (
    app_id INT NOT NULL REFERENCES dim_app(app_id),
    update_id TEXT NOT NULL,
    timestamp_id BIGINT REFERENCES dim_timestamp(timestamp_id),
    etl_run_id BIGINT NOT NULL REFERENCES dim_etl_run(etl_run_id),
    update_type_id INT REFERENCES dim_update_typ(update_type_id),
    title TEXT NOT NULL,
    url TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (app_id, update_id),
    FOREIGN KEY (app_id, update_id) REFERENCES dim_update_content(app_id, update_id)
);

-- Fact: SteamSpy statistics snapshot
CREATE TABLE IF NOT EXISTS fact_steamspy_stats (
    stats_id BIGSERIAL PRIMARY KEY,
    timestamp_id BIGINT NOT NULL REFERENCES dim_timestamp(timestamp_id),
    etl_run_id BIGINT NOT NULL REFERENCES dim_etl_run(etl_run_id),
    app_id INT NOT NULL REFERENCES dim_app(app_id),
    owners_min INT,
    owners_max INT,
    ccu INT,
    positive INT,
    negative INT,
    userscore INT,
    average_forever INT,
    median_forever INT,
    average_2weeks INT,
    median_2weeks INT,
    price NUMERIC(12,2),
    initialprice NUMERIC(12,2),
    discount NUMERIC(5,2),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (owners_min IS NULL OR owners_max IS NULL OR owners_min <= owners_max)
);

-- Indexes to speed up joins
CREATE INDEX IF NOT EXISTS idx_fact_news_ts ON fact_news (timestamp_id);
CREATE INDEX IF NOT EXISTS idx_fact_news_app ON fact_news (app_id);
CREATE INDEX IF NOT EXISTS idx_fact_news_etl ON fact_news (etl_run_id);
CREATE INDEX IF NOT EXISTS idx_fact_steamspy_ts ON fact_steamspy_stats (timestamp_id);
CREATE INDEX IF NOT EXISTS idx_fact_steamspy_app ON fact_steamspy_stats (app_id);
CREATE INDEX IF NOT EXISTS idx_fact_steamspy_etl ON fact_steamspy_stats (etl_run_id);
CREATE INDEX IF NOT EXISTS idx_fact_steamspy_app_ts ON fact_steamspy_stats (app_id, timestamp_id);
CREATE INDEX IF NOT EXISTS idx_fact_news_app_ts ON fact_news (app_id, timestamp_id);
