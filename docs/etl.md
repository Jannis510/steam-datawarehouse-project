# ETL-Prozess

Diese Dokumentation beschreibt den Aufbau, Ablauf und die Designentscheidungen des ETL-Prozesses des Steam Data Warehouse Projekts.

Der ETL vereinheitlicht Daten aus der **Steam News API** und der **SteamSpy API** und persistiert diese in einem relationalen PostgreSQL-DWH. Die Ausführung erfolgt containerisiert (Docker) oder lokal.


## Überblick

**Datenfluss**

Steam News API
SteamSpy API
→ Python-ETL
→ PostgreSQL Data Warehouse
→ (optional) Apache Superset

**Datenmodell**

Das Zielschema ist ein Snowflake-Schema mit folgenden zentralen Tabellen:

* Fakten:

  * `fact_news`
  * `fact_steamspy_stats`
* Dimensionen:

  * `dim_app`
  * `dim_timestamp`
  * `dim_update_typ`
  * `dim_update_content`
  * `dim_etl_run`

Details zum Feldmapping sind in folgenden Dokumenten beschrieben:

* `docs/mapping-steam-news.md`
* `docs/mapping-steamspy.md`



## ETL-Varianten

Der ETL unterstützt zwei Betriebsarten:

* **Initial Run:**
  Erstbefüllung des DWH mit vollständigem Datenbestand (innerhalb definierter Limits)

* **Incremental Run:**
  Nachladen neuer Steam-News und neuer SteamSpy-Snapshots seit dem letzten Lauf


## ETL-Ablauf: Initial Run

### 1. Setup & Initialisierung

* Optionale `.env`-Datei wird geladen (`load_env_if_present`)
* Datenbankverbindung wird über `POSTGRES_*`-Variablen aufgebaut
* Neuer Eintrag in `dim_etl_run` wird angelegt (`run_type = initial`)

Zweck:

* Nachvollziehbarkeit
* Laufzeit- und Status-Tracking jedes ETL-Runs


### 2. Phase SteamSpy Snapshot

* Abruf des Endpoints `all` der SteamSpy API
* Für jede App:

  * `upsert_app()` aktualisiert Stammdaten in `dim_app`
  * `insert_steamspy_snapshot()` schreibt Snapshot-Metriken in `fact_steamspy_stats`

Transformationen:

* `owners`-Range wird in `owners_min` / `owners_max` gesplittet
* Preisfelder werden normalisiert
* Snapshot wird pro ETL-Run eindeutig referenziert

Technische Details:

* Savepoint pro App
* Logging von Fortschritt und Fehlern
* Commit nach Abschluss der gesamten SteamSpy-Phase


### 3. Phase Steam News (vollständig)

* Alle Apps aus `dim_app` werden verarbeitet
* Pro App:

  * `fetch_news_for_app()` lädt News seitenweise
  * Pagination über `enddate` (von neu nach alt)
  * Abbruch bei leerer Seite oder Limit

Insert-Logik pro News-Item:

* `dim_timestamp`: Upsert (Cache-basiert)
* `dim_update_typ`: Upsert (Tag-Klassifikation)
* `dim_update_content`: Insert-only
  (PK: `app_id`, `update_id`)
* `fact_news`: Insert-only
  (PK: `app_id`, `update_id`)

Robustheit:

* Savepoint pro News-Item
* Duplikate werden gezählt und übersprungen
* Fehlende Felder führen zum Skip des Items
* Optionales Commit-Intervall (`COMMIT_EVERY_APPS`)


### 4. Abschluss

* `dim_etl_run` wird finalisiert
* Status: `success` oder `failed`
* Laufzeit und Metadaten bleiben historisiert erhalten


## ETL-Ablauf: Incremental Run

Der Incremental Run unterscheidet sich nur in der Steam-News-Phase.

### SteamSpy

* Neuer Snapshot wird immer geladen
* `dim_app` wird weiterhin upserted

### Steam News (inkrementell)

* Letzter verarbeiteter Timestamp pro App wird ermittelt
  (`fetch_latest_news_timestamps`)
* `fetch_news_for_app()` erhält einen Cutoff-Timestamp
* Abbruch, sobald News älter oder gleich dem Cutoff sind
* Insert-Logik identisch zum Initial Run

Ziel:

* Minimale API-Last
* Keine erneute Verarbeitung alter News


## HTTP-Verhalten & Robustheit

### SteamSpy API

* Retry-Logik mit Exponential Backoff

### Steam News API

* HTTP 403: App wird übersprungen
* HTTP 429:

  * Sleep gemäß `Retry-After` (1–60 s)
  * danach erneuter Request
* Umfangreiches Logging (Seiten, Duplikate, Skips)


## Container- & Cron-Ablauf

### Docker-Entrypoint (`etl_entrypoint.sh`)

1. Initial-Run wird ausgeführt
2. Falls `ETL_CRON_SCHEDULE` gesetzt:

   * Cron-Daemon wird gestartet

### Cron-Job

* `run_incremental_cron.py`
* Lädt Environment-Variablen
* Startet `steam_etl_incremental.py`


## Designentscheidungen & Limitationen

* Append-only Facts (keine Korrekturen historischer Daten)
* Keine separate Data-Quality-Schicht
* `update_id` ist nur pro App eindeutig → zusammengesetzter Schlüssel
* Fokus auf Nachvollziehbarkeit und Reproduzierbarkeit statt Produktivbetrieb


## Zusammenfassung
Der ETL-Prozess ist bewusst modular, robust und nachvollziehbar gestaltet.
Er erlaubt sowohl eine vollständige Erstbefüllung als auch inkrementelle Aktualisierungen und bildet eine saubere Grundlage für Analyse und Visualisierung im Data Warehouse.
