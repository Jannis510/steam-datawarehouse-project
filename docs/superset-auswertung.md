# Superset und Auswertung

Dieses Dokument beschreibt kurz:
- wie Superset im Projekt automatisch funktioniert,
- wie man Superset alternativ manuell einrichtet,
- welche SQL-Views für die Auswertung gebaut wurden,
- und welche 3 Dashboards enthalten sind.

## 1) Superset automatisch (empfohlen)

Voraussetzung:
- Dashboard-Exporte liegen in `imports/superset` (im Repo bereits vorhanden)
- In `.env` ist `SUPERSET_IMPORT_DASHBOARDS=1` gesetzt (Default in `.env.example`)

Start:

```bash
docker compose up -d
docker compose --profile superset up -d --build superset
```

Was dabei automatisch passiert (`docker/superset/superset-init.sh`):
1. Superset-Metadatenbank wird migriert (`superset db upgrade`).
2. Admin-User wird erstellt oder Passwort wird gesetzt.
3. Superset wird initialisiert (`superset init`).
4. ZIP-Exporte aus `imports/superset` werden einmalig importiert.
5. Die Datenbankverbindung zum DWH wird durch die Import-Patches auf `DWH_SQLALCHEMY_URI` gesetzt.

Wichtig:
- Der Dashboard-Import ist absichtlich nur einmalig (Marker-Datei in `superset_home`).
- Für erneuten Auto-Import den Superset-Volume-Inhalt/Marker entfernen.

## 2) Superset manuell (Alternative)

Falls Auto-Import deaktiviert ist (`SUPERSET_IMPORT_DASHBOARDS=0`) oder alles manuell importiert werden soll:

1. Superset starten und als Admin einloggen (`http://localhost:8088`).
2. Datenbank anlegen:
   - `Settings -> Database Connections -> + Database`
   - SQLAlchemy URI: `postgresql+psycopg2://dwh:dwh@postgres:5432/dwh`
3. Dashboard importieren:
   - `Settings -> Import dashboards`
   - ZIP aus `imports/superset/*.zip` hochladen
4. Falls nötig Datasets einmal prüfen (`vw_*` Views aus Schema `dwh`).


## 3) Verwendete Views für die Auswertung

Quelle: `docker/postgres/init/003_views.sql`

- `dwh.vw_app_metrics_by_etl_run`
  Zweck: Metrik-Snapshot je `(etl_run_id, app_id)`.
- `dwh.vw_app_news_7d_30d_asof_etl_run`
  Zweck: News-Fenster (7/30 Tage) relativ zum Run-Zeitpunkt.
  Hinweis: Für Performance auf die letzten 30 erfolgreichen Runs begrenzt.
- `dwh.vw_app_overview_by_etl_run`
  Zweck: Zentrale Auswertungs-View je Run und App (Metriken + News + Ratio `ccu_per_news_30d`).
- `dwh.vw_app_overview_latest_etl_run`
  Zweck: Nur der zuletzt erfolgreiche ETL-Run (global).
- `dwh.vw_app_overview_latest_by_app`
  Zweck: Aktueller Stand je App (KPI-Karten im App-Detail-Dashboard).
- `dwh.vw_app_news_latest`
  Zweck: Neueste News je App inkl. `rn` (Latest-N Listen).
- `dwh.vw_app_news_daily`
  Zweck: News pro Tag und App.
- `dwh.vw_app_timeseries_by_etl_run`
  Zweck: Zeitreihen je App über ETL-Runs.
- `dwh.vw_app_changes_by_etl_run`
  Zweck: Delta-Analyse gegen den vorherigen Run.

## 4) Die 3 Dashboards

### A) App-Detail pro Spiel
Datei: `imports/superset/dashboard_app_details.zip`

Fokus:
- Drilldown auf eine App (Filter `App Name`)
- Aktuelle KPIs (CCU, Preis, News 7/30 Tage, CCU pro News)
- Verlauf über ETL-Runs (CCU, Preis, Discount, News)
- News-Kontext (Latest News + Daily News)

Verwendete Datasets/Views:
- `vw_app_overview_latest_by_app`
- `vw_app_overview_latest_etl_run`
- `vw_app_timeseries_by_etl_run`
- `vw_app_news_latest`
- `vw_app_news_daily`

Screenshot am Beispiel Witcher 3: 

![App Details (Beispiel Witcher 3)](img/Witcher3.jpg)

### B) Allgemeines Dashboard: Latest ETL Snapshot
Datei: `imports/superset/dashboard_latest_elt.zip`

Fokus:
- Querschnitt über alle Spiele auf Basis des letzten erfolgreichen Runs
- Kennzahlen-Distribution und Segmente
- Zusammenhang News-Aktivitaet vs. CCU
- ETL-Run-Monitoring (Anzahl Runs / Laufzeit)

Verwendete Datasets/Views:
- `vw_app_overview_latest_etl_run`
- `dim_etl_run`

Screenshot:

![Latest ETL Snapshot](img/latest_etl.jpg)

### C) Allgemeines Dashboard: Run Explorer
Datei: `imports/superset/dashboard_run_explorer.zip`

Fokus:
- Analyse nach ausgewähltem ETL-Run (Filter `etl_run_id`)
- Vergleich von Kennzahlen zwischen Runs
- Geeignet für tägliche ETL-Läfe (Run für Run nachvollziehen)
- Aufbau des Dashboard identisch zum Latest ETL Snapshot (Latest ELT = Run Explorer mit dem neusten Abgeschlossenen Run)

Verwendete Datasets/Views:
- `vw_app_overview_by_etl_run`
- `dim_etl_run`

Hinweis zum 30-Tage-Kontext:
- Die News-30-Tage-Werte kommen aus der run-gebundenen Logik der View `vw_app_news_7d_30d_asof_etl_run`.
- Damit ist ein Run-basierter Vergleich möglich, auch wenn ETL täglich läuft.

## 5) Generelle Anmerkungen
Bei laufenden ETL-Prozessen kann es vorkommen, dass einzelne Grafiken vorübergehend nicht vollständig oder inkonsistent sind. Der Grund ist, dass mehrere Auswertungen auf run-basierten Views (etl_run_id) und dem Laufstatus in dim_etl_run aufbauen. Deshalb sollten Dashboards erst final bewertet werden, wenn der jeweilige ETL-Run vollständig mit dem Status success abgeschlossen ist.
Außerdem werden aktuell bewusst nicht alle im Datenmodell verfügbaren Kennzahlen in den Dashboards genutzt. Es existieren zusätzliche Metriken wie average_forever, median_forever, average_2weeks, median_2weeks sowie weitere Delta-Kennzahlen, die theoretisch ebenfalls visualisiert werden können. Für die aktuelle Auswertung lag der Fokus jedoch auf zentralen KPIs (z. B. CCU, News 7/30 Tage, Preis/Discount, Run-Vergleich), um die Dashboards übersichtlich und interpretierbar zu halten. Eine spätere Erweiterung um weitere Metriken ist ohne Schemaänderung möglich.
