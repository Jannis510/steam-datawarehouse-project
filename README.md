# Datenmodell-Dokumentation – Steam News & SteamSpy Data Warehouse

## 1. Überblick

Dieses Data Warehouse integriert zwei unabhängige Datenquellen: Steam News API und SteamSpy API. Die Daten werden strukturiert in einem Star Schema abgelegt, bestehend aus Faktentabellen und Dimensionstabellen.

## 1.1 Schnellstart mit Docker

1. Docker & Docker Compose installieren.
2. Beispiel-Umgebung kopieren und bei Bedarf anpassen:

   ```bash
   cp .env.example .env
   ```

3. Container starten (Standard ohne Superset):

   ```bash
   docker compose up -d
   ```

   Optional (Superset):

   ```bash
   docker compose --profile superset up -d superset
   ```

   Standardstart bringt Postgres + pgAdmin hoch; Superset ist optional per Profile.

4. Dienste (Standardwerte aus `.env.example`):
   * **PostgreSQL**: `localhost:5432`, DB `dwh`, User/Pass `dwh`/`dwh`
   * **pgAdmin4** (Web-UI): http://localhost:5050 (Login: `admin@example.com` / `admin`)
   * **Apache Superset**: http://localhost:8088 (Login: `admin` / `admin`, konfigurierbar in `.env`)

4. pgAdmin bringt den Postgres-Server bereits vorkonfiguriert mit und verbindet sich automatisch. Falls pgAdmin bereits einmal gestartet wurde, kann das importierte Server-Setup im Volume fehlen; in dem Fall `docker compose down -v` ausfuehren und neu starten.

### Daten-Dump automatisch importieren (optional)

Wenn du einen Data-only Dump hast, kannst du ihn beim ersten Start automatisch laden:

1. Dump-Datei in `dumps/` ablegen (Ordner wird lokal angelegt, bleibt in Git ignoriert).
2. In `.env` die Datei setzen, z. B.:
   ```bash
   POSTGRES_DUMP_FILE=/dumps/dwh_data.dump
   POSTGRES_SMOKE_TEST=1
   ```
3. `docker compose up -d` starten.

Hinweise:
* Der Import laeuft **nur beim ersten Start** mit leerem Volume (Docker-Init).
* Unterstuetzte Formate: `.sql` (data-only) sowie Custom Dumps `.dump` / `.backup`.
* Der Smoke-Test wird nach dem Import ausgefuehrt, wenn `POSTGRES_SMOKE_TEST=1` gesetzt ist.

### Data-only Dump erzeugen

Nutze diese Kommandos, um einen Data-only Dump im Custom-Format zu erstellen:

```bash
docker compose exec -T postgres pg_dump -U dwh -d dwh --data-only --format=c -f /tmp/dwh_data.dump
docker compose cp postgres:/tmp/dwh_data.dump dumps/dwh_data.dump
```

### ETL ausführen

**Lokal (Host)**

1. Python-Abhängigkeiten installieren:
   ```bash
   pip install -r requirements.txt
   ```

2. Environment konfigurieren (für lokale Läufe `POSTGRES_HOST=localhost` setzen, im Container-Verbund `postgres`):
   ```bash
   cp .env.example .env
   ```

3. ETL starten:
   ```bash
   python scripts/steam_etl_initial.py
   ```

**Im Docker-Compose-Stack**

* Standard `docker compose up` startet nur Postgres + pgAdmin. Für ETL und Superset müssen Profile explizit aktiviert werden.

* Einmaligen ETL-Run starten (profil-gated, damit der Service nicht automatisch mit hochfährt):
  ```bash
  docker compose --profile etl up --build etl
  ```
  Der Service nutzt automatisch `POSTGRES_HOST=postgres` und lädt zusätzlich Werte aus `.env`.
  Hinweis: Beim Container-Start wird der ETL immer einmal initial ausgeführt.

* Wiederkehrenden ETL-Run konfigurieren (optional):
  * In `.env` kann ein Cron-Intervall gesetzt werden, z. B. täglich um Mitternacht:
    ```bash
    ETL_CRON_SCHEDULE=0 0 * * *
    ```
  * Hinweis: Der inkrementelle Lauf führt immer einen vollständigen SteamSpy-Snapshot aus.
  * Beim Container-Start wird der ETL **einmal** vollständig ausgeführt. Danach läuft standardmäßig ein **inkrementeller** ETL-Run (nur neue News seit dem letzten Timestamp) gemäß Cron-Intervall.
  * Optional kann das Cron-Skript überschrieben werden:
    ```bash
    ETL_CRON_SCRIPT=/app/scripts/steam_etl_incremental.py
    ```

* ETL + Superset + pgAdmin in einem Kommando hochfahren:
  ```bash
  docker compose --profile etl --profile superset up --build etl superset pgadmin
  ```
  Dabei läuft das ETL einmal durch, während Superset und pgAdmin weiter als UI-Container verfügbar bleiben.

### Apache Superset verwenden

* Superset nutzt eine eigene Metadaten-Datenbank `superset` in Postgres (`docker/postgres/init/002_superset_user.sql`) und startet mit persistentem Volume `superset-home`.
* Zugangsdaten und Port koennen in `.env` angepasst werden (z. B. `SUPERSET_ADMIN_USERNAME`, `SUPERSET_ADMIN_PASSWORD`, `SUPERSET_PORT`).
* Verbindung zum DWH in Superset anlegen:
  * **SQLAlchemy URI**: `postgresql+psycopg2://dwh:dwh@postgres:5432/dwh` (Standard via `DWH_SQLALCHEMY_URI`)
  * Host ist innerhalb des Docker-Netzwerks `postgres`.
* Nach einem ETL-Run steht das DWH-Schema `dwh` fuer Dashboards und Charts bereit.
* Beispiel-Abfragen liegen in `docker/postgres/init/sql queries` und koennen in Superset oder pgAdmin verwendet werden.
* Hinweis: Wenn `SUPERSET_DB_*` in `.env` geändert werden, muss auch `docker/postgres/init/002_superset_user.sql` angepasst werden.

### Superset Dashboards automatisch importieren (optional)

Die Dashboards aus `imports/superset` koennen beim ersten Start automatisch importiert werden:

1. Sicherstellen, dass die ZIP-Exports in `imports/superset` liegen.
2. In `.env` aktivieren:
   ```bash
   SUPERSET_IMPORT_DASHBOARDS=1
   SUPERSET_IMPORT_DIR=/app/imports
   SUPERSET_IMPORT_OVERWRITE=1
   ```
3. `docker compose --profile superset up -d superset` starten.

Hinweise:
* Der Import laeuft nur einmal (Marker in `superset-home`). Fuer einen erneuten Import den Marker loeschen oder das Volume neu erstellen.
* Maskierte Passwoerter in den ZIP-Exports werden beim Import automatisch ersetzt. Quelle ist `SUPERSET_IMPORT_SQLALCHEMY_URI` (falls gesetzt), sonst `DWH_SQLALCHEMY_URI`.

**Warum sehe ich keine Tabellen?**

* Beim allerersten Start mit leerem Volume legt Postgres das Schema automatisch aus `docker/postgres/init/001_create_schema.sql` an.
* Falls das Volume schon existiert hat (z. B. von einem früheren Testlauf), wird das Init-Skript nicht erneut ausgeführt. In dem Fall können Sie entweder das Volume löschen oder das Schema manuell nachziehen:

  ```bash
  # Volumes komplett neu erzeugen (löscht vorhandene Daten)
  docker compose down -v
  docker compose up -d

  # oder: Schema manuell auf die bestehende DB anwenden
  ./scripts/apply_schema.sh
  ```

### Smoke-Test (schneller Check)

Nach einem ETL-Run kann ein kurzer Smoke-Test ausgefuehrt werden:

**Linux/macOS**

```bash
cat scripts/smoke_test.sql | docker compose exec -T postgres psql -U dwh -d dwh
```

**Windows (PowerShell)**

```powershell
Get-Content scripts\smoke_test.sql | docker compose exec -T postgres psql -U dwh -d dwh
```

---

## 2. ER-Modell (Star Schema)
![ER Modell](docs/img/dwh.drawio.png)


---

## 3. Mapping: Steam News API → DWH

### Beispiel-API Response

```
{
  "gid": "1816307528930061",
  "title": "Counter-Strike 2 Update",
  "url": "https://steamstore-a.akamaihd.net/news/...",
  "is_external_url":true,
  "author":"Piggles ULTRAPRO",
  "contents":"[p]...",
  "feedlabel":"Community Announcements",
  "date":1763082076,
  "feedname":"steam_community_announcements",
  "feed_type":1,
  "appid":730,
  "tags":["patchnotes"]
}
```

### Mapping-Tabelle

| API-Feld          | Ziel im DWH                                        | Begründung                       |
| ----------------- | -------------------------------------------------- | -------------------------------- |
| `gid`             | FACT_NEWS.update_id & DIM_UPDATE_CONTENT.update_id | Primärschlüssel für Event & Text |
| `title`           | FACT_NEWS.title                                    | Metadatum des Ereignisses        |
| `url`             | FACT_NEWS.url                                      | Identifiziert das Ereignis       |
| `appid`           | FACT_NEWS.app_id → DIM_APP.app_id                  | Spielreferenz                    |
| `date`            | FACT_NEWS.timestamp_id → DIM_TIMESTAMP             | Zeitdimension                    |
| `tags[0]`         | FACT_NEWS.update_type_id → DIM_UPDATE_TYP          | Klassifikation                   |
| `contents`        | DIM_UPDATE_CONTENT.content_raw                     | Volltext                         |
| `author`          | DIM_UPDATE_CONTENT.author                          | Dokumentmetadatum                |
| `feedlabel`       | DIM_UPDATE_CONTENT.feedlabel                       | Dokumentmetadatum                |
| `feedname`        | DIM_UPDATE_CONTENT.feedname                        | Dokumentmetadatum                |
| `feed_type`       | DIM_UPDATE_CONTENT.feedtype                        | Dokumentmetadatum                |
| `is_external_url` | DIM_UPDATE_CONTENT.is_external_url                 | Dokumentmetadatum                |
| `tags` (alle)     | DIM_UPDATE_CONTENT.tags_raw                        | Vollständiger Rohinhalt          |

---

## 4. Mapping: SteamSpy API → DWH

### Beispiel-API Response

```
{
  "730":{
    "appid":730,
    "name":"Counter-Strike: Global Offensive",
    "developer":"Valve",
    "publisher":"Valve",
    "positive":7642084,
    "negative":1173003,
    "userscore":0,
    "owners":"100,000,000 .. 200,000,000",
    "average_forever":33464,
    "average_2weeks":737,
    "median_forever":6341,
    "median_2weeks":299,
    "price":"0",
    "initialprice":"0",
    "discount":"0",
    "ccu":1013936
  }
}
```

### Mapping-Tabelle

| API-Feld          | Ziel im DWH                                 | Begründung             |
| ----------------- | ------------------------------------------- | ---------------------- |
| `appid`           | FACT_STEAMSPY_STATS.app_id & DIM_APP.app_id | Fremdschlüssel         |
| `name`            | DIM_APP.app_name                            | Stammdatum             |
| `developer`       | DIM_APP.developer                           | Stammdatum             |
| `publisher`       | DIM_APP.publisher                           | Stammdatum             |
| `owners`          | owners_min / owners_max                     | Zeitabhängige Range    |
| `ccu`             | FACT_STEAMSPY_STATS.ccu                     | Zeitabhängige Metrik   |
| `positive`        | FACT_STEAMSPY_STATS.positive                | Zeitabhängige Metrik   |
| `negative`        | FACT_STEAMSPY_STATS.negative                | Zeitabhängige Metrik   |
| `userscore`       | FACT_STEAMSPY_STATS.userscore               | Zeitabhängig           |
| `average_forever` | FACT_STEAMSPY_STATS.average_forever         | Zeitabhängig           |
| `median_forever`  | FACT_STEAMSPY_STATS.median_forever          | Zeitabhängig           |
| `average_2weeks`  | FACT_STEAMSPY_STATS.average_2weeks          | Zeitabhängig           |
| `median_2weeks`   | FACT_STEAMSPY_STATS.median_2weeks           | Zeitabhängig           |
| `price`           | FACT_STEAMSPY_STATS.price                   | preislich zeitabhängig |
| `initialprice`    | FACT_STEAMSPY_STATS.initialprice            | zeitabhängig           |
| `discount`        | FACT_STEAMSPY_STATS.discount                | zeitabhängig           |

---

## 5. Ladeverhalten (ETL)

### FACT_NEWS

* Insert-only
* Keine Updates, kein Überschreiben

### FACT_STEAMSPY_STATS

* Insert-only pro Fetch
* Zeitreihen entstehen über `timestamp_id`

### DIM_APP

* Insert bei neuen Apps
* Updates bei veränderten Stammdaten

### DIM_TIMESTAMP

* Insert wenn neuer Timestamp

### DIM_UPDATE_TYP

* Insert bei unbekannten Tags

### DIM_UPDATE_CONTENT

* Insert-only
* Bewahrt vollständige Dokumente

---

## 6. DWH-Schema (DDL)

Die Docker-Initialisierung legt das Schema `dwh` automatisch an (`docker/postgres/init/001_create_schema.sql`). Wichtige Tabellen:

* **dim_timestamp** – Zeitdimension mit berechneten Jahr/Monat/Tag/ Stunde-Spalten (Timestamps werden als UTC ohne Zeitzone gespeichert, damit die berechneten Spalten immutable bleiben).
* **dim_app** – Stammdaten zu Apps (Name, Developer, Publisher).
* **dim_update_typ** – Klassifikation der Update-Typen (Tags).
* **dim_update_content** – Volltexte und Metadaten der Steam-News-Updates.
* **fact_news** – Ereignisse aus Steam News, referenziert die obigen Dimensionen.
* **fact_steamspy_stats** – Zeitreihensnapshots der SteamSpy-Statistiken.

Jede Tabelle besitzt grundlegende Indizes für Timestamp- und App-bezogene Joins, sodass Abfragen direkt nach dem Container-Start performant möglich sind.


---

## 7. Architektur & ETL Flow (Kurz)

1. Quelle SteamSpy API (JSON) -> Snapshot in `fact_steamspy_stats`
2. Quelle Steam News API (JSON) -> `dim_update_content` + `fact_news`
3. Dimensionen: `dim_app`, `dim_timestamp`, `dim_update_typ`, `dim_etl_run`
4. Auswertung: SQL in `docker/postgres/init/sql queries` oder Superset/pgAdmin

---

## 8. Projektstruktur (Repo)

* `docker/` - Postgres, ETL, Superset Container
* `scripts/` - ETL Code und Entry-Point
* `docs/` - ER-Modell und Abgabe-Dokumente
* `README.md` - Setup, Mapping, Schema

---

## 9. Abgabe-Checkliste (Soll-Orte im Repo)

* SQL-Dump: `exports/dwh_dump.sql`
* ERM/Schema-Grafik: `docs/img/dwh.drawio.png`
* Programmcode: `scripts/`, `docker/`
* Kurzbericht (3-5 Seiten): `docs/report/report.md` oder `docs/report/report.pdf`
* Kurzpraesentation: `docs/presentation/` (Slides/PDF)


## SQL-Dump / Datenbasis

Der vollständige Datenbank-Dump (Custom-Format) wurde aufgrund der Dateigröße
nicht im Git-Repository abgelegt.

- Format: PostgreSQL Custom Backup (.backup)
- Erzeugung: pgAdmin (Docker), nach vollständigem Initial-ETL
- Validierung: Restore-Test in separater Datenbank + Smoke-Checks

Download (Hessenbox):
https://next.hessenbox.de/index.php/s/abzGnaj43oW6fwd
